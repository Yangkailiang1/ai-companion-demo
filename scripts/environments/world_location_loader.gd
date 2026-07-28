# Roadmap: S2.1, S4.1
# Responsibility: Select and replace the active WorldLocation scene; does not
# generate geometry or own character behavior.
# Collaborators: ParametricRoomRuntime, living_room.tscn
# Tests: scripts/debug/world_location_loader_check.gd

class_name WorldLocationLoader
extends Node3D

signal location_loaded(mode: String, location: Node3D)

const LEGACY_ROOM_PATH := "res://scenes/living_room.tscn"
const PARAMETRIC_ROOM_PATH := \
	"res://scenes/environments/parametric_living_room_runtime.tscn"

@export_enum("legacy", "parametric") var default_world_mode := "legacy"

var current_mode := ""
var _active_location: Node3D
var _retire_serial := 0


## [S2.1][S4.1] 在 WorldRoot 入树时解析环境覆盖并装载首个地点。
## `AI_GAMES_WORLD_MODE=parametric` 可启用生成客厅，非法值安全回退 legacy。
func _enter_tree() -> void:
	var requested_mode := OS.get_environment("AI_GAMES_WORLD_MODE").strip_edges()
	if requested_mode.is_empty():
		requested_mode = default_world_mode
	switch_location(requested_mode)


## [S2.1] 原子替换当前地点；加载失败时回退 legacy，返回实际加载模式。
## 副作用：释放旧地点、实例化新地点并发出 location_loaded。
func switch_location(requested_mode: String) -> String:
	var resolved_mode := _normalize_mode(requested_mode)
	var scene_path := (
		PARAMETRIC_ROOM_PATH if resolved_mode == "parametric"
		else LEGACY_ROOM_PATH
	)
	var packed := load(scene_path) as PackedScene
	if packed == null and resolved_mode != "legacy":
		resolved_mode = "legacy"
		packed = load(LEGACY_ROOM_PATH) as PackedScene
	if packed == null:
		push_error("WorldLocationLoader: no loadable room scene")
		return ""
	_clear_active_location()
	_active_location = packed.instantiate()
	_active_location.name = "LivingRoom"
	add_child(_active_location)
	current_mode = resolved_mode
	location_loaded.emit(current_mode, _active_location)
	return current_mode


## [S2.1] 返回当前地点节点；纯读取。
func get_active_location() -> Node3D:
	return _active_location


## [S2.1] 将未知模式收敛到公开兼容的 legacy 模式；纯函数。
func _normalize_mode(requested_mode: String) -> String:
	return requested_mode if requested_mode in ["legacy", "parametric"] else "legacy"


## [S2.1] 隐藏旧地点并给予异步角色协程两帧收尾，再安全释放。
## 旧地点在宽限期内保留树连接，避免 await 恢复到已销毁实例。
func _clear_active_location() -> void:
	if not is_instance_valid(_active_location):
		return
	var retired := _active_location
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
