# Roadmap: C6.2, C2.1, C3.1
# Responsibility: 管理静态和运行时角色适配合同，提供语义动作/骨骼/表情查询；
# 不加载模型、不播放动画，也不决定剧情。
# Collaborators: CharacterRuntimeBinding, CharacterAnimationDriver, CharacterExpressionDriver
# Tests: scripts/debug/character_adapter_coverage_check.gd

extends Node

const CONFIG_PATH := "res://data/character_runtime_adapters.json"
const REQUIRED_ACTIONS := ["idle", "walk", "wave", "nod", "think", "happy", "sit", "talk"]

signal runtime_adapter_registered(agent_id: String)
signal runtime_adapter_unregistered(agent_id: String)

var _config: Dictionary = {}
var _characters: Dictionary = {}
var _runtime_agent_ids: Dictionary = {}
var _last_error := ""


## [C6.2] 加载随项目发布的角色适配配置。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_config()


## [C6.2] 返回角色完整适配合同；未知角色返回空对象，禁止误用主角配置。
func get_character_adapter(agent_id: String) -> Dictionary:
	return _characters.get(agent_id, {})


## [C2.1] 返回角色动作适配合同；纯读取。
func get_motion_adapter(agent_id: String) -> Dictionary:
	return get_character_adapter(agent_id).get("motion_adapter", {})


## [C2.1] 返回角色骨骼适配合同；纯读取。
func get_skeleton_adapter(agent_id: String) -> Dictionary:
	return get_character_adapter(agent_id).get("skeleton_adapter", {})


## [C3.1] 返回角色表情适配合同；纯读取。
func get_expression_adapter(agent_id: String) -> Dictionary:
	return get_character_adapter(agent_id).get("expression_adapter", {})


## [C3.1] 返回语义表情到模型 morph 的别名映射；纯读取。
func get_expression_channel_map(agent_id: String) -> Dictionary:
	return get_expression_adapter(agent_id).get("channel_map", {})


## [C2.1] 返回角色动作后端类型；未知角色使用安全 procedural 类型。
func get_motion_adapter_type(agent_id: String) -> String:
	return String(get_motion_adapter(agent_id).get("type", "procedural_root_fallback"))


## [C6.2][D1] 返回已注册的角色 ID 列表，供编剧 cast 白名单使用。
func get_registered_agent_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in _characters.keys():
		ids.append(String(key))
	ids.sort()
	return ids


## [C2.1] 把共享 action_id 映射为当前模型 clip 或程序化动作 ID。
func map_clip(agent_id: String, action_id: String, fallback_clip: String = "idle") -> String:
	var clip_map: Dictionary = get_motion_adapter(agent_id).get("clip_map", {})
	return String(clip_map.get(action_id, fallback_clip))


## [C6.2] 注册场景随附的 Q 版角色适配器。
## 前置：agent_id 唯一，动作与表情合同完整；失败不改变注册表。
func register_runtime_adapter(agent_id: String, adapter: Dictionary) -> bool:
	var clean_id := agent_id.strip_edges()
	_last_error = _validate_adapter(clean_id, adapter)
	if not _last_error.is_empty():
		return false
	if _characters.has(clean_id) and not _runtime_agent_ids.has(clean_id):
		_last_error = "不能覆盖项目内置角色: %s" % clean_id
		return false
	_characters[clean_id] = adapter.duplicate(true)
	_runtime_agent_ids[clean_id] = true
	runtime_adapter_registered.emit(clean_id)
	return true


## [C6.2] 移除由场景动态注册的角色；内置角色不受影响。
func unregister_runtime_adapter(agent_id: String) -> void:
	if not _runtime_agent_ids.has(agent_id):
		return
	_runtime_agent_ids.erase(agent_id)
	_characters.erase(agent_id)
	runtime_adapter_unregistered.emit(agent_id)


## [C6.2][X5.1] 返回最近一次运行时注册错误；不包含模型或贴图数据。
func get_last_error() -> String:
	return _last_error


## [C6.2] 校验跨模型共享动作集合和表情映射的最小合同。
func _validate_adapter(agent_id: String, adapter: Dictionary) -> String:
	if agent_id.is_empty():
		return "agent_id 不能为空"
	var motion: Dictionary = adapter.get("motion_adapter", {})
	var clips: Dictionary = motion.get("clip_map", {})
	for action_id in REQUIRED_ACTIONS:
		if not clips.has(action_id) or String(clips[action_id]).is_empty():
			return "%s 缺少动作映射: %s" % [agent_id, action_id]
	var expression: Dictionary = adapter.get("expression_adapter", {})
	var channels: Dictionary = expression.get("channel_map", {})
	var expression_type := String(expression.get("type", "blend_shapes"))
	if channels.is_empty() and expression_type != "bone_fallback":
		return "%s 缺少表情 channel_map" % agent_id
	if expression_type == "bone_fallback":
		var skeleton: Dictionary = adapter.get("skeleton_adapter", {})
		if skeleton.get("expression_bone_map", {}).is_empty():
			return "%s 的 bone_fallback 缺少 expression_bone_map" % agent_id
	return ""


## [C6.2] 从版本化 JSON 读取内置适配器，解析失败时保持空注册表。
func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		push_warning("CharacterAdapterRegistry: missing %s" % CONFIG_PATH)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not parsed is Dictionary:
		push_warning("CharacterAdapterRegistry: invalid adapter config")
		return
	_config = parsed
	_characters = _config.get("characters", {}).duplicate(true)
