# codified_profile.gd — 角色逻辑编码 (Autoload)
# 设计文档 §十：Codified Profile [CCL §3.2]
# 用确定性的 check_condition + if-then-else 替代纯 Prompt 描述角色

extends Node

var agent_id: String = "main_agent"
var profile_name: String = "小叶子"
var profile_data: Dictionary = {}


func _ready():
	_load_profile()


func _load_profile():
	var path = "res://data/character_config.json"
	if not FileAccess.file_exists(path):
		_create_default_profile()
		return
	var file = FileAccess.open(path, FileAccess.READ)
	if not file: return
	var content = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(content) == OK:
		profile_data = json.get_data()


func _create_default_profile():
	profile_data = {
		"name": "小叶子",
		"age": 20,
		"personality": "活泼开朗，有点小迷糊，特别喜欢喝奶茶",
		"seed_memories": [
			"小叶子是一个活泼可爱的女孩，喜欢奶茶的一切",
			"小叶子住在客厅旁边的小房间，每天都会在客厅活动",
			"小叶子对玩家很友好，把玩家当作好朋友",
			"小叶子不喜欢吵架，遇到冲突会试图用幽默化解",
			"小叶子早上喜欢赖床，晚上反而精神好"
		],
		"rules": [
			{"condition": "有人送礼物给小叶子", "reaction": "开心接受", "emotion": "happy", "intensity": 0.9},
			{"condition": "有人批评小叶子", "reaction": "委屈但嘴硬", "emotion": "sad", "intensity": 0.5},
			{"condition": "奶茶在附近且超过2小时没喝", "reaction": "想去喝奶茶", "random_prob": 0.3},
			{"condition": "窗外阳光很好", "reaction": "心情变好", "emotion": "happy", "intensity": 0.3},
			{"condition": "天黑了还一个人", "reaction": "有点害怕", "emotion": "nervous", "intensity": 0.4},
		]
	}


# === 核心函数：给定场景和世界状态，输出角色逻辑触发的断言 [CCL §3.2] ===

func parse_by_scene(semantic_snapshot: String, player_message: String = "") -> Array:
	var triggered=  []

	for rule in profile_data.get("rules", []):
		var condition: String = rule["condition"]
		var matched = _check_local_condition(condition, semantic_snapshot, player_message)

		if not matched:
			continue

		# 随机概率 — 可控随机性 [CCL §3.4]
		if rule.has("random_prob"):
			if randf() > rule["random_prob"]:
				continue

		triggered.append({
			"reaction": rule["reaction"],
			"emotion": rule.get("emotion", "neutral"),
			"intensity": rule.get("intensity", 0.5),
		})

	return triggered


# === 本地条件检测（关键词/规则匹配 — 不调 LLM） ===

func _check_local_condition(condition: String, semantic_snapshot: String, player_message: String) -> bool:
	var lower_cond = condition.to_lower()
	var lower_snapshot = semantic_snapshot.to_lower()
	var lower_msg = player_message.to_lower()

	# 奶茶相关
	if "奶茶" in lower_cond and "奶茶" in lower_snapshot:
		return true

	# 阳光相关
	if "阳光" in lower_cond and "阳光" in lower_snapshot:
		return true

	# 天黑相关
	if "天黑" in lower_cond or "夜晚" in lower_cond:
		if "夜晚" in lower_snapshot or "傍晚" in lower_snapshot:
			return true

	# 送礼相关
	if "礼物" in lower_cond and "礼物" in lower_msg:
		return true

	# 批评相关
	if "批评" in lower_cond or "指责" in lower_cond:
		for word in ["批评", "指责", "骂", "不好", "笨蛋", "傻瓜"]:
			if word in lower_msg:
				return true

	return false


# === 获取角色身份信息 ===

func get_identity() -> String:
	var lines=  []
	lines.append("你是%s。" % profile_data.get("name", "未知角色"))
	lines.append("性格：%s。" % profile_data.get("personality", ""))
	lines.append("以下是你一直知道的事情：")
	for seed in profile_data.get("seed_memories", []):
		lines.append("- " + seed)
	return "\n".join(lines)


# === 获取已触发的角色逻辑描述（给 LLM 看） ===

func get_triggered_log(triggered: Array) -> String:
	if triggered.is_empty():
		return ""
	var lines=  []
	lines.append("[自动触发的角色反应]")
	for t in triggered:
		lines.append("- " + t["reaction"])
	return "\n".join(lines)
