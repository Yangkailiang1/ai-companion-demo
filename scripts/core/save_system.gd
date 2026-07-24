extends Node

const SCHEMA_VERSION := 1
const DEFAULT_SAVE_PATH := "user://world_save_v1.json"

var save_file_path := DEFAULT_SAVE_PATH
var last_error := ""
var _pending_agent_states: Dictionary = {}
var _autosave_timer: Timer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = 60.0
	_autosave_timer.timeout.connect(func(): save_game())
	add_child(_autosave_timer)
	call_deferred("_try_auto_load")


func save_game(path: String = "") -> Error:
	var target := path if not path.is_empty() else save_file_path
	var absolute_target := ProjectSettings.globalize_path(target)
	var parent_dir := absolute_target.get_base_dir()
	var mkdir_error := DirAccess.make_dir_recursive_absolute(parent_dir)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		last_error = "cannot create save directory: %s (error %d)" % [parent_dir, mkdir_error]
		return mkdir_error
	var file := FileAccess.open(target, FileAccess.WRITE)
	if not file:
		last_error = "cannot open save for writing: %s" % target
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(_build_snapshot(), "\t"))
	file.close()
	last_error = ""
	MessageBus.world_state_changed.emit("game_saved", {"path": target, "schema_version": SCHEMA_VERSION})
	return OK


func load_game(path: String = "") -> Error:
	var target := path if not path.is_empty() else save_file_path
	if not FileAccess.file_exists(target):
		last_error = "save file does not exist: %s" % target
		return ERR_FILE_NOT_FOUND
	var file := FileAccess.open(target, FileAccess.READ)
	if not file:
		last_error = "cannot open save for reading: %s" % target
		return FileAccess.get_open_error()
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not json.data is Dictionary:
		last_error = "invalid save JSON: %s" % target
		return ERR_PARSE_ERROR
	var data: Dictionary = json.data
	if int(data.get("schema_version", 0)) != SCHEMA_VERSION:
		last_error = "unsupported save schema: %s" % data.get("schema_version", 0)
		return ERR_FILE_UNRECOGNIZED
	WorldSimulator.import_save_state(data.get("world", {}))
	SemanticWorld.import_save_state(data.get("objects", {}))
	if has_node("/root/AgentPsycheSystem"):
		get_node("/root/AgentPsycheSystem").import_save_state(data.get("psychology", {}))
	_pending_agent_states = data.get("agents", {}).duplicate(true)
	_apply_pending_agent_states()
	last_error = ""
	MessageBus.world_state_changed.emit("save_loaded", {"path": target, "schema_version": SCHEMA_VERSION})
	return OK


func get_snapshot() -> Dictionary:
	return _build_snapshot()


func _build_snapshot() -> Dictionary:
	var agents := {}
	for node in get_tree().get_nodes_in_group("agents"):
		if not node is Node3D:
			continue
		var agent_id := String(node.get("agent_name"))
		if agent_id.is_empty():
			continue
		agents[agent_id] = {
			"position": _vec3_to_array((node as Node3D).global_position),
			"rotation": _vec3_to_array((node as Node3D).rotation),
			"activity": String(node.get("current_activity")),
			"emotion": String(node.get("current_emotion")),
		}
	return {
		"schema_version": SCHEMA_VERSION,
		"saved_at_unix": Time.get_unix_time_from_system(),
		"world": WorldSimulator.export_save_state(),
		"objects": SemanticWorld.export_save_state(),
		"psychology": AgentPsycheSystem.export_save_state(),
		"agents": agents,
	}


func _apply_pending_agent_states() -> void:
	for node in get_tree().get_nodes_in_group("agents"):
		var agent_id := String(node.get("agent_name"))
		if not _pending_agent_states.has(agent_id):
			continue
		var state: Dictionary = _pending_agent_states[agent_id]
		(node as Node3D).global_position = _array_to_vec3(state.get("position", []), (node as Node3D).global_position)
		(node as Node3D).rotation = _array_to_vec3(state.get("rotation", []), (node as Node3D).rotation)
		node.set("current_activity", String(state.get("activity", "idle")))
		node.set("current_emotion", String(state.get("emotion", "neutral")))


func _try_auto_load() -> void:
	if get_tree().current_scene == null:
		return
	if FileAccess.file_exists(save_file_path):
		load_game(save_file_path)
	_autosave_timer.start()


func _on_node_added(_node: Node) -> void:
	if not _pending_agent_states.is_empty():
		call_deferred("_apply_pending_agent_states")


func _vec3_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _array_to_vec3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback
