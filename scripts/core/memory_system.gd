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
const REFLECTION_THRESHOLD: float = 150.0
var accumulated_importance: float = 0.0

var memory_file_path: String = "user://memories.json"


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_memories()


# === 写操作 ===

func add_episode(content: String, importance: float = 5.0) -> void:
	var entry = {
		"timestamp": Time.get_unix_time_from_system(),
		"content": content,
		"importance": importance,
	}
	episode_memory.append(entry)
	accumulated_importance += importance

	# 限制内存大小
	while episode_memory.size() > MAX_EPISODES:
		episode_memory.pop_front()

	# 检查是否需要触发反思
	if accumulated_importance >= REFLECTION_THRESHOLD:
		request_reflection()
		accumulated_importance = 0.0

	_save_memories()


func set_semantic(key: String, value: String) -> void:
	semantic_memory[key] = value
	_save_memories()


func update_relationship(target: String, field: String, delta: float) -> void:
	if not relationship_memory.has(target):
		relationship_memory[target] = {"trust": 0.3, "affinity": 0.3, "respect": 0.3, "familiarity": 0.0}
	relationship_memory[target][field] = clamp(relationship_memory[target][field] + delta, -1.0, 1.0)
	_save_memories()


# === 读操作 (检索) ===
# 参考 [GA §4.2.2]: score(m) = α·recency(m) + β·importance(m) + γ·relevance(query, m)

func retrieve_relevant(query: String, top_k: int = 5, alpha: float = 1.0, beta: float = 1.0, gamma: float = 1.0) -> Array:
	var now = Time.get_unix_time_from_system()
	var scored=  []

	for ep in episode_memory:
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


func retrieve_semantic(key: String) -> String:
	return semantic_memory.get(key, "")


# === 反思模块 [GA §4.3] ===

func request_reflection() -> void:
	# 反思需要 LLM 处理，这里发出信号让 CognitiveCycle 处理
	MessageBus.world_state_changed.emit("reflection_needed", {
		"recent_episodes": episode_memory.slice(max(0, episode_memory.size() - 20)),
	})


func add_reflection(content: String) -> void:
	# LLM 生成的反思结果存入 Episode Memory
	add_episode("[反思] " + content, 8.0)


# === 格式化输出（给 LLM 用）===

func format_for_llm(query: String = "") -> String:
	var lines=  []

	# 最近记忆
	var recent = retrieve_relevant(query, 5)
	if not recent.is_empty():
		lines.append("[近期记忆]")
		for ep in recent:
			lines.append("- " + ep["content"])

	# 关系状态
	var rel = retrieve_relationship("player")
	lines.append("[与玩家的关系] 信任:%.1f 好感:%.1f 关系:%s" % [rel["trust"], rel["affinity"], rel.get("role", "未知")])

	return "\n".join(lines)


# === 持久化 ===

func _save_memories() -> void:
	var data = {
		"episodes": episode_memory.slice(max(0, episode_memory.size() - 200)),
		"semantic": semantic_memory,
		"relationship": relationship_memory,
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
		if data.has("episodes"): episode_memory = data["episodes"]
		if data.has("semantic"): semantic_memory = data["semantic"]
		if data.has("relationship"): relationship_memory = data["relationship"]


# === 简易相关性计算（词重合度） ===
func _simple_relevance(query: String, text: String) -> float:
	if query.is_empty(): return 0.5
	var query_words = query.to_lower().split(" ", false)
	var text_lower = text.to_lower()
	var hits = 0
	for w in query_words:
		if w in text_lower: hits += 1
	return float(hits) / max(query_words.size(), 1)
