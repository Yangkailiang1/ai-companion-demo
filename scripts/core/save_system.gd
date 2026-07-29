extends Node

# Roadmap: X1, T4.5, S2.2
# Responsibility: Manage versioned JSON save/load with cross-location agent
# and semantic-object persistence; does not own world state, semantics,
# psychology, navigation, or UI.
# Collaborators: WorldSimulator, SemanticWorld, AgentPsycheSystem,
# WorldLocationLoader, MessageBus
# Tests: scripts/debug/save_plant_state_check.gd,
# scripts/debug/cross_location_save_check.gd

const SCHEMA_VERSION := 2
const DEFAULT_SAVE_PATH := "user://world_save_v2.json"
const LEGACY_SAVE_PATH := "user://world_save_v1.json"

var save_file_path := DEFAULT_SAVE_PATH
var last_error := ""
var _pending_agent_states: Dictionary = {}
var _autosave_timer: Timer


## [T4.5] 连接节点信号并在场景就绪后尝试自动加载存档。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = 60.0
	_autosave_timer.timeout.connect(func(): save_game())
	add_child(_autosave_timer)
	call_deferred("_try_auto_load")


## [X1][T4.5] 将当前世界序列化为带版本号的 JSON 快照。
## 副作用：写入文件并发出 world_state_changed 信号；未找到 WorldLocationLoader
## 时 location 块使用默认值。
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


## [X1.2][T4.5] 加载并恢复存档快照。
## 副作用：可能触发地点旅行、导入世界/语义/心理学状态、存储挂起的 Agent 状态。
## 对 parametric 模式暂不立即应用 Agent 位置，由 ParametricRoomRuntime 在生成
## 出生点阶段后触发。
func load_game(path: String = "") -> Error:
	var target := path if not path.is_empty() else _resolve_default_save_path()
	if not FileAccess.file_exists(target):
		last_error = "save file does not exist: %s" % target
		return ERR_FILE_NOT_FOUND
	var data := _load_and_validate_json(target)
	if data.is_empty():
		return ERR_PARSE_ERROR
	var schema_value = data.get("schema_version", null)
	if not schema_value is int and not schema_value is float:
		last_error = "invalid save: schema_version must be an integer"
		return ERR_INVALID_DATA
	var schema := int(schema_value)
	if not is_equal_approx(float(schema_value), float(schema)):
		last_error = "invalid save: schema_version must be an integer"
		return ERR_INVALID_DATA
	if schema == 1:
		data = _migrate_v1_to_v2(data)
	elif schema == SCHEMA_VERSION:
		pass
	else:
		last_error = "unsupported save schema: %d (supported: 1, %d)" % [schema, SCHEMA_VERSION]
		return ERR_FILE_UNRECOGNIZED
	if data.is_empty() or not _validate_snapshot(data):
		return ERR_INVALID_DATA
	var loader := _resolve_loader()
	if loader != null and data.get("residency", null) is Dictionary:
		var residency = loader.get_residency_registry()
		if residency != null and not residency.import_save_state(data.residency):
			last_error = "failed to restore agent residency"
			return ERR_INVALID_DATA
	var location_ok := _restore_location(data.get("location", {}))
	if not location_ok:
		last_error = "failed to restore location from save"
		return ERR_CANT_OPEN
	WorldSimulator.import_save_state(data.get("world", {}))
	SemanticWorld.import_save_state(data.get("objects", {}))
	if has_node("/root/AgentPsycheSystem"):
		get_node("/root/AgentPsycheSystem").import_save_state(data.get("psychology", {}))
	_pending_agent_states = data.get("agents", {}).duplicate(true)
	loader = _resolve_loader()
	if loader != null and loader.has_method("reconcile_active_cast"):
		loader.reconcile_active_cast()
	if loader == null or loader.current_mode == "legacy":
		_apply_pending_agent_states()
	elif _is_active_room_spawn_ready(loader):
		_apply_pending_agent_states()
	last_error = ""
	MessageBus.world_state_changed.emit("save_loaded", {"path": target, "schema_version": SCHEMA_VERSION})
	return OK


## [X1] 返回当前运行时快照；纯读取。
func get_snapshot() -> Dictionary:
	return _build_snapshot()


## [X1.2] 在参数化房间写入出生点后，消费匹配该地点的 Agent 存档状态。
## 副作用：仅当参数与当前地点一致时修改活动房间中的 Agent。
func apply_pending_agent_states_for_location(location_id: String) -> void:
	var loader := _resolve_loader()
	if loader == null or loader.current_location_id != location_id:
		return
	_apply_pending_agent_states()


## [X1.2] 构建带 version 2 字段的完整快照。
func _build_snapshot() -> Dictionary:
	var agents := {}
	var loader := _resolve_loader()
	var active_location_id := "living_room"
	var active_room: Node = null
	if loader != null:
		active_location_id = loader.current_location_id
		active_room = loader.get_active_location()
	for node in get_tree().get_nodes_in_group("agents"):
		if not node is Node3D:
			continue
		if active_room != null and not active_room.is_ancestor_of(node):
			continue
		var agent_id := String(node.get("agent_name"))
		if agent_id.is_empty():
			continue
		agents[agent_id] = {
			"position": _vec3_to_array((node as Node3D).global_position),
			"rotation": _vec3_to_array((node as Node3D).rotation),
			"activity": String(node.get("current_activity")),
			"emotion": String(node.get("current_emotion")),
			"location_id": active_location_id,
		}
	var world_mode := "legacy"
	var residency_state := {}
	if loader != null:
		world_mode = loader.current_mode
		var residency = loader.get_residency_registry()
		if residency != null:
			residency_state = residency.export_save_state()
	return {
		"schema_version": SCHEMA_VERSION,
		"saved_at_unix": Time.get_unix_time_from_system(),
		"location": {
			"world_mode": world_mode,
			"location_id": active_location_id,
		},
		"world": WorldSimulator.export_save_state(),
		"objects": SemanticWorld.export_save_state(),
		"psychology": AgentPsycheSystem.export_save_state(),
		"residency": residency_state,
		"agents": agents,
	}


## [X1.2][S2.2] 将待恢复状态应用到活动房间中匹配当前位置的 Agent。
## 副作用：修改 Agent 位置/旋转/活动/情绪；
## 位置不匹配的 Agent 条目跳过，保留供后续旅行恢复。
## 匹配条目成功应用后立即消费，避免以后回房间重复跳回旧坐标。
func _apply_pending_agent_states() -> void:
	var loader := _resolve_loader()
	var active_location_id := "living_room"
	var active_room: Node = null
	if loader != null:
		active_location_id = loader.current_location_id
		active_room = loader.get_active_location()
	for node in get_tree().get_nodes_in_group("agents"):
		if not node is Node3D:
			continue
		if active_room != null and not active_room.is_ancestor_of(node):
			continue
		var agent_id := String(node.get("agent_name"))
		if not _pending_agent_states.has(agent_id):
			continue
		var state: Dictionary = _pending_agent_states[agent_id]
		if String(state.get("location_id", "")) != active_location_id:
			continue
		if node.has_method("cancel_movement"):
			node.cancel_movement("save_load")
		var body := node as CharacterBody3D
		if body != null:
			body.velocity = Vector3.ZERO
		var navigation_agent := node.get_node_or_null(
			"NavigationAgent3D"
		) as NavigationAgent3D
		if navigation_agent != null:
			navigation_agent.velocity = Vector3.ZERO
		(node as Node3D).global_position = _array_to_vec3(state.get("position", []), (node as Node3D).global_position)
		(node as Node3D).rotation = _array_to_vec3(state.get("rotation", []), (node as Node3D).rotation)
		node.set("current_activity", String(state.get("activity", "idle")))
		node.set("current_emotion", String(state.get("emotion", "neutral")))
		_pending_agent_states.erase(agent_id)


## [X1.2] 尝试自动加载存档：优先 v2，回退 v1。
func _try_auto_load() -> void:
	if get_tree().current_scene == null:
		return
	if FileAccess.file_exists(save_file_path):
		load_game(save_file_path)
	elif FileAccess.file_exists(LEGACY_SAVE_PATH):
		load_game(LEGACY_SAVE_PATH)
	_autosave_timer.start()


## [T4.5] legacy 节点入树时尝试消费挂起状态；参数化房间由出生点后钩子处理。
func _on_node_added(_node: Node) -> void:
	var loader := _resolve_loader()
	if not _pending_agent_states.is_empty() and (
		loader == null or loader.current_mode == "legacy"
	):
		call_deferred("_apply_pending_agent_states")


## [X1.2] 从存档数据恢复世界模式和地点。
## 副作用：可能触发地点旅行（parametric）或 legacy 切换；
## 非法模式/地点保护当前房间并返回 false。
## 已在目标模式/位置时跳过以保护上下文引用。
func _restore_location(location_data: Dictionary) -> bool:
	var loader := _resolve_loader()
	if loader == null:
		return true
	var world_mode := String(location_data.get("world_mode", ""))
	if world_mode.is_empty():
		return true
	if world_mode not in ["legacy", "parametric"]:
		push_error("SaveSystem: unsupported world mode %s" % world_mode)
		return false
	var location_id := String(location_data.get("location_id", ""))
	if world_mode == "legacy":
		if location_id != "living_room":
			return false
		if loader.current_mode == "legacy" and loader.current_location_id == "living_room":
			return true
		var actual := loader.switch_location("legacy")
		return actual == "legacy"
	if location_id.is_empty():
		return false
	if loader.current_mode == "parametric" and loader.current_location_id == location_id:
		return true
	return loader.travel_to(location_id)


## [X1.2] 将 v1 快照内存迁移为 v2 格式。
## 旧 v1 保存使用 legacy 模式和默认 living_room 位置。
func _migrate_v1_to_v2(data: Dictionary) -> Dictionary:
	var migrated := data.duplicate(true)
	migrated["schema_version"] = SCHEMA_VERSION
	if not migrated.has("location"):
		migrated["location"] = {"world_mode": "legacy", "location_id": "living_room"}
	var raw_agents = migrated.get("agents", {})
	if not raw_agents is Dictionary:
		last_error = "invalid v1 save: agents must be an object"
		return {}
	var agents: Dictionary = raw_agents.duplicate(true)
	for agent_id in agents:
		if not agents[agent_id] is Dictionary:
			last_error = "invalid v1 save: agent state must be an object"
			return {}
		var agent_data: Dictionary = agents[agent_id].duplicate(true)
		if not agent_data.has("location_id"):
			agent_data["location_id"] = "living_room"
		agents[agent_id] = agent_data
	migrated["agents"] = agents
	return migrated


## [X1.2] 在任何运行时变更前校验 v2 顶层、地点和 Agent 坐标合同。
## 副作用：失败时只写 last_error。
func _validate_snapshot(data: Dictionary) -> bool:
	for key in ["location", "world", "objects", "agents"]:
		if not data.get(key, null) is Dictionary:
			last_error = "invalid save: %s must be an object" % key
			return false
	if data.has("psychology") and not data.psychology is Dictionary:
		last_error = "invalid save: psychology must be an object"
		return false
	if data.has("residency") and not data.residency is Dictionary:
		last_error = "invalid save: residency must be an object"
		return false
	var location: Dictionary = data.location
	if not location.get("world_mode", null) is String or not (
		location.get("location_id", null) is String
	):
		last_error = "invalid save location types"
		return false
	var mode: String = location.world_mode
	var location_id: String = location.location_id
	if mode not in ["legacy", "parametric"] or location_id.is_empty():
		last_error = "invalid save location contract"
		return false
	if mode == "legacy" and location_id != "living_room":
		last_error = "invalid legacy location: %s" % location_id
		return false
	for agent_id in data.agents:
		var state = data.agents[agent_id]
		if not state is Dictionary or not _is_vec3_array(state.get("position", [])):
			last_error = "invalid agent position: %s" % agent_id
			return false
		if not _is_vec3_array(state.get("rotation", [])):
			last_error = "invalid agent rotation: %s" % agent_id
			return false
		if not state.get("location_id", null) is String or state.location_id.is_empty():
			last_error = "missing agent location: %s" % agent_id
			return false
	return true


## [X1.2] 判断 Variant 是否为三个数值组成的 JSON 数组；纯函数。
func _is_vec3_array(value: Variant) -> bool:
	if not value is Array or value.size() < 3:
		return false
	for index in range(3):
		if not value[index] is float and not value[index] is int:
			return false
	return true


## [X1.2] 读取并校验 JSON 文件的 schema 版本号。
## 失败或已识别的未知版本返回空 Dictionary，不修改运行时。
func _load_and_validate_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		last_error = "cannot open save for reading: %s" % path
		return {}
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not json.data is Dictionary:
		last_error = "invalid save JSON: %s" % path
		return {}
	return json.data


## [X1.2] 解析存档路径：优先 v2，回退 v1（自动加载用）。
func _resolve_default_save_path() -> String:
	if FileAccess.file_exists(DEFAULT_SAVE_PATH):
		return DEFAULT_SAVE_PATH
	if FileAccess.file_exists(LEGACY_SAVE_PATH):
		return LEGACY_SAVE_PATH
	return DEFAULT_SAVE_PATH


## [X1.2] 解析 WorldRoot 上的 WorldLocationLoader；纯读取。
func _resolve_loader() -> WorldLocationLoader:
	var root := get_tree().current_scene
	if root == null:
		return null
	var wr := root.get_node_or_null("WorldRoot")
	if wr is WorldLocationLoader:
		return wr
	return null


## [X1.2] 查询活动参数化房间是否已写入声明出生点；纯读取。
func _is_active_room_spawn_ready(loader: WorldLocationLoader) -> bool:
	var room := loader.get_active_location()
	return room != null and room.has_method("are_location_spawns_restored") and (
		room.are_location_spawns_restored()
	)


## [X1] 三维向量转换为 JSON 数组。
func _vec3_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


## [X1] JSON 数组转换为三维向量，带安全回退。
func _array_to_vec3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback
