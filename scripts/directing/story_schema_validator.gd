# Roadmap: D1
# Responsibility: 纯验证与规范化 JSON 剧本数据；不访问场景树、不执行演出。
# Collaborators: PerformanceCueTypes, RoomNavigation
# Tests: scripts/debug/story_director_check.gd

extends RefCounted

const VALID_GESTURES: PackedStringArray = ["idle", "walk", "wave", "nod", "think", "happy", "sit", "talk", "offline_smoke_walk"]
const VALID_EXPRESSIONS: PackedStringArray = [
	"neutral", "happy", "angry", "sad", "surprised", "excited", "bored", "blink", "talk",
]
const VALID_OBJECTS: PackedStringArray = ["sofa", "tv", "book", "milk_tea", "plant"]
const VALID_INTERACTIONS := {
	"sofa": ["sit", "lie_down"],
	"tv": ["turn_on", "turn_off", "watch", "change_channel"],
	"book": ["read", "pick_up", "put_down"],
	"milk_tea": ["drink", "pick_up", "put_down", "throw"],
	"plant": ["water", "prune", "look_at"],
}
const PAUSE_MIN: float = 0.1
const PAUSE_MAX: float = 5.0
const MAX_BEATS: int = 80

var _allowed_cast: Array[String] = []
var _errors: Array = []


## [D1] 构造验证器。allowed_cast 指定允许的角色 ID 白名单，默认用于独立测试。
func _init(allowed_cast: Array = []) -> void:
	var source: Array = allowed_cast if not allowed_cast.is_empty() else ["main_agent", "jue_agent"]
	for actor_id in source:
		_allowed_cast.append(String(actor_id))


## [D1] 执行完整校验流程：结构→角色→节奏→路点→对象→动作→表达。
## 返回 true 表示通过校验，false 时调用 get_errors() 获取结构化错误。
func validate(document: Dictionary) -> bool:
	_errors.clear()
	if not _check_structure(document):
		return false
	var beats_raw = document["beats"]
	if not beats_raw is Array:
		_add_error("root", "beats 必须是数组")
		return false
	var beats: Array = beats_raw
	if beats.size() > MAX_BEATS:
		_add_error("root", "剧本节拍数 %d 超过上限 %d" % [beats.size(), MAX_BEATS])
		return false
	var cast: Array = document.get("cast", [])
	for i in range(beats.size()):
		_validate_beat(i, beats[i], cast)
	return _errors.is_empty()


## [D1] 返回结构化错误列表，每个错误包含 {path, message}。
func get_errors() -> Array:
	return _errors.duplicate(true)


## [D1] 返回通过校验的规范化副本：补充默认值、清理无效 key。
func normalize(document: Dictionary) -> Dictionary:
	if not validate(document):
		return {}
	var result: Dictionary = {
		"schema_version": int(document.get("schema_version", 1)),
		"story_id": String(document.get("story_id", "")),
		"title": String(document.get("title", "")),
		"cast": [],
		"beats": [],
		"memory_summary": String(document.get("memory_summary", "")),
	}
	var cast_raw = document.get("cast", [])
	if cast_raw is Array:
		result["cast"] = cast_raw.duplicate(true)
	var beats_raw = document.get("beats", [])
	if beats_raw is Array:
		for beat in beats_raw:
			if beat is Dictionary:
				result["beats"].append(_normalize_beat(beat))
	return result


## [D1] 追加一个带字段路径的稳定验证错误。
func _add_error(path: String, message: String) -> void:
	_errors.append({"path": path, "message": message})


## [D1] 校验顶层结构：必需字段、类型、schema_version 和 cast 白名单。
func _check_structure(document: Dictionary) -> bool:
	if not document is Dictionary:
		_add_error("root", "文档必须是 JSON 对象")
		return false
	for field in ["story_id", "title", "cast", "beats"]:
		if not document.has(field):
			_add_error("root", "缺少必需字段: %s" % field)
			return false
	var cast_raw = document.get("cast")
	if not cast_raw is Array:
		_add_error("root", "cast 必须是数组")
		return false
	var cast_arr: Array = cast_raw
	if cast_arr.is_empty():
		_add_error("root", "cast 不能为空")
		return false
	var seen: Dictionary = {}
	for actor in cast_arr:
		if not actor is String:
			_add_error("cast", "cast 成员必须是字符串，收到 %s" % typeof(actor))
			return false
		var actor_str: String = actor
		if actor_str not in _allowed_cast:
			_add_error("cast", "不支持的角色: %s" % actor_str)
			return false
		if seen.has(actor_str):
			_add_error("cast", "重复角色: %s" % actor_str)
			return false
		seen[actor_str] = true
	var beats_raw = document.get("beats")
	if not beats_raw is Array:
		_add_error("root", "beats 必须是数组")
		return false
	var schema_version = document.get("schema_version", 1)
	if not (schema_version is int or schema_version is float):
		_add_error("root", "schema_version 必须是数字")
		return false
	# 顶层字段白名单校验
	for key_raw in document:
		var key: String = key_raw if key_raw is String else String(key_raw)
		if key not in ["schema_version", "story_id", "title", "cast", "beats", "memory_summary"]:
			_add_error("root", "不允许的顶层字段: %s" % key)
			return false
	return true


## [D1] 校验单个 beat：类型检查和字段合法性后，委托子校验器。
func _validate_beat(index: int, beat_raw: Variant, cast: Array) -> void:
	if not beat_raw is Dictionary:
		_add_error("beats[%d]" % index, "节拍必须是 JSON 对象")
		return
	var beat: Dictionary = beat_raw
	if not _check_beat_allowed_fields(beat, index):
		return
	if not _validate_beat_actor(beat, index, cast):
		return
	_validate_beat_move_to(beat, index)
	_validate_beat_look_at(beat, index, cast)
	_validate_beat_interaction(beat, index)
	_validate_beat_gesture(beat, index)
	_validate_beat_expression(beat, index)
	_validate_beat_say(beat, index)
	_validate_beat_pause(beat, index)


## [D1] 检查 beat 是否包含不允许的字段。返回 true 表示通过。
func _check_beat_allowed_fields(beat: Dictionary, index: int) -> bool:
	var allowed: Array[String] = [
		"actor", "move_to", "look_at_actor", "look_at_object",
		"interact", "gesture", "expression", "say", "pause_after",
	]
	for key_raw in beat:
		var key: String = key_raw if key_raw is String else String(key_raw)
		if not allowed.has(key):
			_add_error("beats[%d]" % index, "不允许的字段: %s" % key)
			return false
	return true


## [D1] 验证 actor 字段：必须存在且属于 document.cast。返回 true 表示通过。
func _validate_beat_actor(beat: Dictionary, index: int, cast: Array) -> bool:
	if not beat.has("actor"):
		_add_error("beats[%d]" % index, "缺少必需字段: actor")
		return false
	var actor = String(beat.get("actor", ""))
	if actor not in cast:
		_add_error("beats[%d].actor" % index, "角色不在 cast 中: %s" % actor)
		return false
	return true


## [D1] 验证 move_to 字段：必须恰好包含 waypoint 或 object 之一，子字段合法。
func _validate_beat_move_to(beat: Dictionary, index: int) -> void:
	if not beat.has("move_to"):
		return
	var move_raw = beat["move_to"]
	if not move_raw is Dictionary:
		_add_error("beats[%d].move_to" % index, "move_to 必须是对象")
		return
	var move: Dictionary = move_raw
	_validate_move_subfields(move, index)
	var ways := _count_move_targets(move)
	if ways != 1:
		_add_error("beats[%d].move_to" % index, "move_to 必须恰好包含 waypoint 或 object 之一，当前有 %d 个" % ways)


## [D1] 统计 move_to 中有效的 waypoint/object 目标数并校验子字段。
func _count_move_targets(move: Dictionary) -> int:
	var ways := 0
	if move.has("waypoint"):
		ways += 1
	if move.has("object"):
		ways += 1
	return ways


## [D1] 校验 move_to 的所有子字段合法性。
func _validate_move_subfields(move: Dictionary, index: int) -> void:
	for move_key_raw in move:
		var move_key: String = move_key_raw if move_key_raw is String else String(move_key_raw)
		if move_key not in ["waypoint", "object"]:
			_add_error("beats[%d].move_to" % index, "move_to 不允许的字段: %s" % move_key)
	if move.has("waypoint"):
		var wp_raw = move.get("waypoint")
		if not wp_raw is String:
			_add_error("beats[%d].move_to.waypoint" % index, "waypoint 必须是字符串")
		else:
			var nav = RoomNavigation.new()
			if not nav.has_waypoint(String(wp_raw)):
				_add_error("beats[%d].move_to.waypoint" % index, "不存在的路点: %s" % wp_raw)
	if move.has("object"):
		var obj_raw = move.get("object")
		if not obj_raw is String:
			_add_error("beats[%d].move_to.object" % index, "object 必须是字符串")
		elif String(obj_raw) not in VALID_OBJECTS:
			_add_error("beats[%d].move_to.object" % index, "不存在的物体: %s" % obj_raw)


## [D1] 验证 look_at 字段：look_at_actor / look_at_object 互斥，目标必须属于 cast。
func _validate_beat_look_at(beat: Dictionary, index: int, cast: Array) -> void:
	if beat.has("look_at_actor") and beat.has("look_at_object"):
		_add_error("beats[%d]" % index, "不能同时设置 look_at_actor 和 look_at_object")
	if beat.has("look_at_actor"):
		var look_raw = beat["look_at_actor"]
		if not look_raw is String:
			_add_error("beats[%d].look_at_actor" % index, "look_at_actor 必须是字符串")
		else:
			var target: String = look_raw
			if target not in cast:
				_add_error("beats[%d].look_at_actor" % index, "角色不在 cast 中: %s" % target)
	if beat.has("look_at_object"):
		var look_raw = beat["look_at_object"]
		if not look_raw is String:
			_add_error("beats[%d].look_at_object" % index, "look_at_object 必须是字符串")
		elif String(look_raw) not in VALID_OBJECTS:
			_add_error("beats[%d].look_at_object" % index, "不存在的物体: %s" % look_raw)


## [D1][S3.2] 验证场景交互：仅允许已知物体声明过的 affordance 动词。
func _validate_beat_interaction(beat: Dictionary, index: int) -> void:
	if not beat.has("interact"):
		return
	var raw = beat["interact"]
	if not raw is Dictionary:
		_add_error("beats[%d].interact" % index, "interact 必须是对象")
		return
	var interaction: Dictionary = raw
	for key in interaction:
		if String(key) not in ["object", "verb"]:
			_add_error("beats[%d].interact" % index, "interact 不允许的字段: %s" % key)
	if not interaction.get("object") is String or not interaction.get("verb") is String:
		_add_error("beats[%d].interact" % index, "object 和 verb 必须是字符串")
		return
	var object_id := String(interaction["object"])
	var verb := String(interaction["verb"])
	if not VALID_INTERACTIONS.has(object_id):
		_add_error("beats[%d].interact.object" % index, "不存在的物体: %s" % object_id)
	elif verb not in VALID_INTERACTIONS[object_id]:
		_add_error("beats[%d].interact.verb" % index, "%s 不支持交互: %s" % [object_id, verb])


## [D1] 验证 gesture 字段：必须属于已知手势白名单。
func _validate_beat_gesture(beat: Dictionary, index: int) -> void:
	if not beat.has("gesture"):
		return
	var g_raw = beat["gesture"]
	if not g_raw is String:
		_add_error("beats[%d].gesture" % index, "gesture 必须是字符串")
	elif String(g_raw) not in VALID_GESTURES:
		_add_error("beats[%d].gesture" % index, "不支持的 gesture: %s" % g_raw)


## [D1] 验证 expression 字段：必须属于已知表情白名单。
func _validate_beat_expression(beat: Dictionary, index: int) -> void:
	if not beat.has("expression"):
		return
	var e_raw = beat["expression"]
	if not e_raw is String:
		_add_error("beats[%d].expression" % index, "expression 必须是字符串")
	elif String(e_raw) not in VALID_EXPRESSIONS:
		_add_error("beats[%d].expression" % index, "不支持的 expression: %s" % e_raw)


## [D1] 验证 say 字段：必须是字符串且非空。
func _validate_beat_say(beat: Dictionary, index: int) -> void:
	if not beat.has("say"):
		return
	var s_raw = beat["say"]
	if not s_raw is String:
		_add_error("beats[%d].say" % index, "say 必须是字符串")
	else:
		var s = String(s_raw)
		if s.is_empty():
			_add_error("beats[%d].say" % index, "say 不能为空字符串")


## [D1] 验证 pause_after 字段：必须是数字且在合法范围内。
func _validate_beat_pause(beat: Dictionary, index: int) -> void:
	if not beat.has("pause_after"):
		return
	var p_raw = beat["pause_after"]
	if not (p_raw is float or p_raw is int):
		_add_error("beats[%d].pause_after" % index, "pause_after 必须是数字")
	else:
		var p = float(p_raw)
		if p < PAUSE_MIN or p > PAUSE_MAX:
			_add_error("beats[%d].pause_after" % index, "pause_after 必须在 %.1f–%.1f 之间，当前为 %.2f" % [PAUSE_MIN, PAUSE_MAX, p])


## [D1] 规范化单个 beat：字段规整、补充默认 pause_after。
func _normalize_beat(beat: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"actor": String(beat["actor"]),
		"pause_after": clampf(float(beat.get("pause_after", 1.5)), PAUSE_MIN, PAUSE_MAX),
	}
	if beat.has("gesture"):
		result["gesture"] = String(beat["gesture"])
	if beat.has("expression"):
		result["expression"] = String(beat["expression"])
	if beat.has("say"):
		result["say"] = String(beat["say"])
	if beat.has("look_at_actor"):
		result["look_at_actor"] = String(beat["look_at_actor"])
	if beat.has("look_at_object"):
		result["look_at_object"] = String(beat["look_at_object"])
	if beat.has("interact"):
		var interaction: Dictionary = beat["interact"]
		result["interact"] = {
			"object": String(interaction["object"]),
			"verb": String(interaction["verb"]),
		}
	if beat.has("move_to"):
		var move_raw = beat["move_to"]
		if not move_raw is Dictionary:
			return result
		var move: Dictionary = move_raw
		result["move_to"] = {}
		if move.has("waypoint"):
			result["move_to"]["waypoint"] = String(move["waypoint"])
		elif move.has("object"):
			result["move_to"]["object"] = String(move["object"])
	return result
