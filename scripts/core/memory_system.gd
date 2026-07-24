# memory_system.gd — 四层结构化记忆系统 (Autoload)
# 设计文档 §六：Episode | Semantic | Affordance | Relationship
# 参考 [GA §4.2-4.3]

extends Node

# === Episode Memory (SQLite 风格 — 用 JSON 文件存储)
# 存储格式: {timestamp, content, importance(1-10)}
var episode_memory=  []
const MAX_EPISODES: int = 500

# === Semantic Memory (键值对)
var semantic_memory: Dictionary = {}

# === Affordance Memory (由 SemanticWorld 管理，这里存 Agent 发现的知识)
var affordance_memory: Dictionary = {}

# === Relationship Memory
var relationship_memory: Dictionary = {
	"player": {"trust": 0.5, "affinity": 0.6, "respect": 0.5, "familiarity": 0.0, "role": "朋友"}
}

# 反思阈值 [GA §4.3]
const REFLECTION_THRESHOLD: float = 45.0
var accumulated_importance: float = 0.0
var accumulated_importance_by_agent: Dictionary = {}

var memory_file_path: String = "user://memories.json"
var agent_memories: Dictionary = {}


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_memories()
	_ensure_agent_memory("main_agent")


# === 写操作 ===

func add_episode(content: String, importance: float = 5.0) -> void:
	add_episode_for_agent("main_agent", content, importance)


func add_episode_for_agent(agent_id: String, content: String, importance: float = 5.0) -> void:
	_ensure_agent_memory(agent_id)
	var entry = {
		"timestamp": Time.get_unix_time_from_system(),
		"content": content,
		"importance": importance,
	}
	agent_memories[agent_id]["episodes"].append(entry)
	episode_memory = agent_memories["main_agent"]["episodes"]
	accumulated_importance_by_agent[agent_id] = float(accumulated_importance_by_agent.get(agent_id, 0.0)) + importance
	if agent_id == "main_agent":
		accumulated_importance = float(accumulated_importance_by_agent[agent_id])

	# 限制内存大小
	while agent_memories[agent_id]["episodes"].size() > MAX_EPISODES:
		agent_memories[agent_id]["episodes"].pop_front()

	# 检查是否需要触发反思
	if float(accumulated_importance_by_agent[agent_id]) >= REFLECTION_THRESHOLD:
		accumulated_importance_by_agent[agent_id] = 0.0
		if agent_id == "main_agent":
			accumulated_importance = 0.0
		request_reflection_for_agent(agent_id)

	_save_memories()


func set_semantic(key: String, value: String) -> void:
	semantic_memory[key] = value
	_save_memories()


func set_semantic_for_agent(agent_id: String, key: String, value: String) -> void:
	_ensure_agent_memory(agent_id)
	agent_memories[agent_id]["semantic"][key] = value
	if agent_id == "main_agent":
		semantic_memory = agent_memories[agent_id]["semantic"]
	_save_memories()


func update_relationship(target: String, field: String, delta: float) -> void:
	update_relationship_for_agent("main_agent", target, field, delta)


func update_relationship_for_agent(agent_id: String, target: String, field: String, delta: float) -> void:
	_ensure_agent_memory(agent_id)
	var relationships: Dictionary = agent_memories[agent_id]["relationship"]
	if not relationships.has(target):
		relationships[target] = {"trust": 0.3, "affinity": 0.3, "respect": 0.3, "familiarity": 0.0}
	relationships[target][field] = clamp(float(relationships[target].get(field, 0.3)) + delta, -1.0, 1.0)
	if agent_id == "main_agent":
		relationship_memory = relationships
	_save_memories()


# === 读操作 (检索) ===
# 参考 [GA §4.2.2]: score(m) = α·recency(m) + β·importance(m) + γ·relevance(query, m)

func retrieve_relevant(query: String, top_k: int = 5, alpha: float = 1.0, beta: float = 1.0, gamma: float = 1.0) -> Array:
	return retrieve_relevant_for_agent("main_agent", query, top_k, alpha, beta, gamma)


func retrieve_relevant_for_agent(agent_id: String, query: String, top_k: int = 5, alpha: float = 1.0, beta: float = 1.0, gamma: float = 1.0) -> Array:
	_ensure_agent_memory(agent_id)
	var now = Time.get_unix_time_from_system()
	var scored=  []

	for ep in agent_memories[agent_id]["episodes"]:
		var age_hours = (now - (ep["timestamp"] as float)) / 3600.0
		var recency = exp(-age_hours / 24.0)  # 24小时半衰期
		var importance = ep["importance"] as float / 10.0
		var relevance = _simple_relevance(query, ep["content"])

		var score = alpha * recency + beta * importance + gamma * relevance
		scored.append({"entry": ep, "score": score})

	scored.sort_custom(func(a, b): return a["score"] > b["score"])
	var result=  []
	for i in range(min(top_k, scored.size())):
		result.append(scored[i]["entry"])

	return result


func retrieve_relationship(target: String) -> Dictionary:
	return relationship_memory.get(target, {"trust": 0.3, "affinity": 0.3})


func retrieve_relationship_for_agent(agent_id: String, target: String) -> Dictionary:
	_ensure_agent_memory(agent_id)
	return agent_memories[agent_id]["relationship"].get(target, {"trust": 0.3, "affinity": 0.3})


func retrieve_semantic(key: String) -> String:
	return semantic_memory.get(key, "")


# === 反思模块 [GA §4.3] ===

func request_reflection() -> void:
	request_reflection_for_agent("main_agent")


func request_reflection_for_agent(agent_id: String) -> void:
	_ensure_agent_memory(agent_id)
	var episodes: Array = agent_memories[agent_id]["episodes"]
	MessageBus.agent_reflection_requested.emit(
		agent_id,
		episodes.slice(max(0, episodes.size() - 20))
	)


func add_reflection(content: String) -> void:
	add_reflection_for_agent("main_agent", content)


func add_reflection_for_agent(agent_id: String, content: String) -> void:
	add_episode_for_agent(agent_id, "[反思] " + content, 8.0)


# === 格式化输出（给 LLM 用）===

func format_for_llm(query: String = "") -> String:
	return format_for_llm_for_agent("main_agent", query)


func format_for_llm_for_agent(agent_id: String, query: String = "") -> String:
	_ensure_agent_memory(agent_id)
	var lines=  []

	# 最近记忆
	var recent = retrieve_relevant_for_agent(agent_id, query, 5)
	if not recent.is_empty():
		lines.append("[近期记忆]")
		for ep in recent:
			lines.append("- " + ep["content"])

	# 关系状态
	var rel = retrieve_relationship_for_agent(agent_id, "player")
	lines.append("[与玩家的关系] 信任:%.1f 好感:%.1f 关系:%s" % [rel["trust"], rel["affinity"], rel.get("role", "未知")])
	for other_agent_id in agent_memories[agent_id]["relationship"]:
		if other_agent_id == "player":
			continue
		var other_rel: Dictionary = agent_memories[agent_id]["relationship"][other_agent_id]
		lines.append("[与%s的关系] 信任:%.1f 好感:%.1f 关系:%s" % [
			other_agent_id,
			float(other_rel.get("trust", 0.3)),
			float(other_rel.get("affinity", 0.3)),
			other_rel.get("role", "同伴")
		])

	return "\n".join(lines)


# === 持久化 ===

func _save_memories() -> void:
	var data = {
		"episodes": episode_memory.slice(max(0, episode_memory.size() - 200)),
		"semantic": semantic_memory,
		"relationship": relationship_memory,
		"agents": _serialize_agent_memories(),
	}
	var file = FileAccess.open(memory_file_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()


func _load_memories() -> void:
	if not FileAccess.file_exists(memory_file_path):
		return
	var file = FileAccess.open(memory_file_path, FileAccess.READ)
	if not file: return
	var content = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(content) == OK:
		var data = json.get_data()
		if data.has("agents") and data["agents"] is Dictionary:
			agent_memories = data["agents"]
		else:
			if data.has("episodes"): episode_memory = data["episodes"]
			if data.has("semantic"): semantic_memory = data["semantic"]
			if data.has("relationship"): relationship_memory = data["relationship"]
			agent_memories["main_agent"] = {
				"episodes": episode_memory,
				"semantic": semantic_memory,
				"relationship": relationship_memory,
			}
	_ensure_agent_memory("main_agent")
	episode_memory = agent_memories["main_agent"]["episodes"]
	semantic_memory = agent_memories["main_agent"]["semantic"]
	relationship_memory = agent_memories["main_agent"]["relationship"]


# === 简易相关性计算（词重合度） ===
func _simple_relevance(query: String, text: String) -> float:
	if query.is_empty(): return 0.5
	var query_words = query.to_lower().split(" ", false)
	var text_lower = text.to_lower()
	var hits = 0
	for w in query_words:
		if w in text_lower: hits += 1
	return float(hits) / max(query_words.size(), 1)


func _ensure_agent_memory(agent_id: String) -> void:
	var normalized := agent_id if not agent_id.is_empty() else "main_agent"
	if not agent_memories.has(normalized):
		agent_memories[normalized] = {
			"episodes": [],
			"semantic": {},
			"relationship": {
				"player": {"trust": 0.5, "affinity": 0.6, "respect": 0.5, "familiarity": 0.0, "role": "朋友"}
			},
		}


func _serialize_agent_memories() -> Dictionary:
	for agent_id in agent_memories:
		var episodes: Array = agent_memories[agent_id].get("episodes", [])
		agent_memories[agent_id]["episodes"] = episodes.slice(max(0, episodes.size() - 200))
	return agent_memories
