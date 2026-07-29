# Roadmap: S2.1, S2.2, P2.3
# Responsibility: Select and replace the active WorldLocation scene; does not
# generate geometry or own character behavior.
# Collaborators: ParametricRoomRuntime, living_room.tscn, WorldTravelPortal
# Tests: scripts/debug/world_location_loader_check.gd

class_name WorldLocationLoader
extends Node3D

signal location_loaded(mode: String, location: Node3D)
signal world_location_loaded(location_id: String, location: Node3D)

const LEGACY_ROOM_PATH := "res://scenes/living_room.tscn"
const PARAMETRIC_ROOM_PATH := \
	"res://scenes/environments/parametric_living_room_runtime.tscn"
const LEGACY_PLAYER_SPAWN := Vector3(0.0, 0.0, -2.2)
const LEGACY_PLAYER_YAW_DEGREES := 180.0

@export_enum("legacy", "parametric") var default_world_mode := "legacy"

var current_mode := ""
var current_location_id := ""
var _active_location: Node3D
var _retire_serial := 0
var _catalog := WorldLocationCatalog.new()


## [S2.1][S4.1] 在 WorldRoot 入树时解析环境覆盖并装载首个地点。
## `AI_GAMES_WORLD_MODE=parametric` 可启用生成客厅，非法值安全回退 legacy。
func _enter_tree() -> void:
	if not _catalog.load_catalog():
		push_error("WorldLocationLoader: location catalog unavailable")
	var requested_mode := OS.get_environment("AI_GAMES_WORLD_MODE").strip_edges()
	if requested_mode.is_empty():
		requested_mode = default_world_mode
	switch_location(requested_mode)


## [S2.1] 原子替换当前地点；加载失败时回退 legacy，返回实际加载模式。
## 副作用：释放旧地点、实例化新地点并发出 location_loaded。
func switch_location(requested_mode: String) -> String:
	var resolved_mode := _normalize_mode(requested_mode)
	if resolved_mode == "parametric":
		return "parametric" if travel_to(_catalog.default_location_id) else ""
	var scene_path := LEGACY_ROOM_PATH
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("WorldLocationLoader: no loadable room scene")
		return ""
	_clear_active_location()
	_active_location = packed.instantiate()
	_active_location.name = "LivingRoom"
	add_child(_active_location)
	_position_player_at_floor(LEGACY_PLAYER_SPAWN, LEGACY_PLAYER_YAW_DEGREES)
	current_mode = resolved_mode
	current_location_id = "living_room"
	_activate_legacy_semantics()
	location_loaded.emit(current_mode, _active_location)
	world_location_loaded.emit(current_location_id, _active_location)
	return current_mode


## [S2.2] 原子装载目录中的参数化地点；非法目标不破坏当前场景。
## 在新地点入树前连接 portal_travel_requested 信号以保证不丢失入口事件。
func travel_to(location_id: String, entry_id: String = "default") -> bool:
	var location := _catalog.get_location(location_id)
	if location.is_empty():
		return false
	var packed := load(String(location.get("scene_path", PARAMETRIC_ROOM_PATH))) as PackedScene
	if packed == null:
		return false
	var next_location := packed.instantiate() as Node3D
	if next_location == null:
		return false
	location["location_id"] = location_id
	location["cast_spawns"] = location.get("cast_spawns", {}).duplicate(true)
	location["cast_members"] = location.get(
		"cast_members", WorldCastAssembler.CAST_NODE_NAMES
	).duplicate()
	if next_location.has_method("configure_location"):
		next_location.configure_location(location)
	next_location.name = String(location.get("root_name", location_id.to_pascal_case()))
	# [S2.2] 在入树前连接入口旅行信号
	if next_location.has_signal("portal_travel_requested"):
		next_location.portal_travel_requested.connect(_on_room_portal_travel_requested)
	_clear_active_location()
	_active_location = next_location
	current_mode = "parametric"
	current_location_id = location_id
	add_child(_active_location)
	_position_player_at_entry(location, entry_id)
	location_loaded.emit(current_mode, _active_location)
	world_location_loaded.emit(current_location_id, _active_location)
	return true


## [S2.2] 沿当前地点的具名出口旅行；出口图无效时保持原地点。
func travel_via(exit_id: String) -> bool:
	if not _catalog.can_travel(current_location_id, exit_id):
		return false
	var edge := _catalog.get_exit(current_location_id, exit_id)
	return travel_to(
		String(edge.get("target_location_id", "")),
		String(edge.get("target_entry_id", "default")),
	)


## [S2.2] 对外暴露只读地点目录查询，供 UI/导演/测试列出出口。
func get_location_catalog() -> WorldLocationCatalog:
	return _catalog


## [S2.1] 返回当前地点节点；纯读取。
func get_active_location() -> Node3D:
	return _active_location


## [S2.1] 将未知模式收敛到公开兼容的 legacy 模式；纯函数。
func _normalize_mode(requested_mode: String) -> String:
	return requested_mode if requested_mode in ["legacy", "parametric"] else "legacy"


## [S2.2][P2.3] 解析地点入口并传送持久玩家身体；AI Cast 出生点不受影响。
func _position_player_at_entry(location: Dictionary, entry_id: String) -> void:
	var entries = location.get("entries", {})
	if entries is Dictionary and entries.has(entry_id):
		var entry: Dictionary = entries[entry_id]
		var rotation := _array_to_vector3(
			entry.get("rotation_deg", []), Vector3(0.0, LEGACY_PLAYER_YAW_DEGREES, 0.0)
		)
		_position_player_at_floor(
			_array_to_vector3(entry.get("position", []), LEGACY_PLAYER_SPAWN),
			rotation.y,
		)


## [P2.3] 将 PlayerBody 放到地面坐标；节点缺失时安全跳过。
func _position_player_at_floor(floor_position: Vector3, yaw_degrees: float) -> void:
	var player := get_node_or_null("PlayerBody")
	if player != null and player.has_method("teleport_to_floor_position"):
		player.teleport_to_floor_position(floor_position, yaw_degrees)


## [S2.2] 接收来自 WorldTravelPortal 的旅行请求，通过 travel_via 执行原子切换。
func _on_room_portal_travel_requested(exit_id: String) -> void:
	travel_via(exit_id)


## [S2.2] 兼容旧客厅时恢复语义可见域。
func _activate_legacy_semantics() -> void:
	var semantic_world := get_node_or_null("/root/SemanticWorld")
	if semantic_world != null and semantic_world.has_method("set_active_location"):
		semantic_world.set_active_location("living_room")


## [S2.1] 隐藏旧地点并给予异步角色协程两帧收尾，再安全释放。
## 旧地点在宽限期内保留树连接，避免 await 恢复到已销毁实例。
func _clear_active_location() -> void:
	if not is_instance_valid(_active_location):
		return
	var retired := _active_location
	if retired.has_method("deactivate_portals"):
		retired.deactivate_portals()
	_active_location = null
	_retire_serial += 1
	retired.name = "RetiringLocation_%d" % _retire_serial
	retired.visible = false
	_free_after_grace_period(retired)


## [S2.1][T4.2] 等待两个 process_frame 后释放退役地点，吸收一帧初始化协程。
func _free_after_grace_period(retired: Node3D) -> void:
	for _frame in range(2):
		await get_tree().process_frame
	if is_instance_valid(retired):
		retired.queue_free()


## [S2.2][P2.3] 将 JSON 三元数组转换为世界坐标。
func _array_to_vector3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback
