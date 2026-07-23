extends Node

const CONFIG_PATH := "res://data/character_runtime_adapters.json"

var _config: Dictionary = {}
var _characters: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_config()


func get_character_adapter(agent_id: String) -> Dictionary:
	if _characters.has(agent_id):
		return _characters[agent_id]
	return _characters.get("main_agent", {})


func get_motion_adapter(agent_id: String) -> Dictionary:
	return get_character_adapter(agent_id).get("motion_adapter", {})


func get_skeleton_adapter(agent_id: String) -> Dictionary:
	return get_character_adapter(agent_id).get("skeleton_adapter", {})


func get_expression_adapter(agent_id: String) -> Dictionary:
	return get_character_adapter(agent_id).get("expression_adapter", {})


func get_expression_channel_map(agent_id: String) -> Dictionary:
	return get_expression_adapter(agent_id).get("channel_map", {})


func get_motion_adapter_type(agent_id: String) -> String:
	return String(get_motion_adapter(agent_id).get("type", "animation_player"))


func map_clip(agent_id: String, action_id: String, fallback_clip: String = "idle") -> String:
	var motion_adapter := get_motion_adapter(agent_id)
	var clip_map: Dictionary = motion_adapter.get("clip_map", {})
	return String(clip_map.get(action_id, fallback_clip))


func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		push_warning("CharacterAdapterRegistry: missing %s" % CONFIG_PATH)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not parsed is Dictionary:
		push_warning("CharacterAdapterRegistry: invalid adapter config")
		return
	_config = parsed
	_characters = _config.get("characters", {})
