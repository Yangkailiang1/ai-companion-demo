# Verifies: S2.1, S4.2, D2
# Covers: generated NavMesh connectivity from both fixed actors to story waypoints.

extends SceneTree

var _failed := false


## [S4.2][D2] 延迟到 NavigationServer 同步后验证剧情路点连通性。
func _init() -> void:
	call_deferred("_run")


## [S2.1][S4.2][D2] 检查两个角色到所有演出关键路点都有完整路径。
func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	for _frame in range(5):
		await physics_frame
	var room := scene.get_node("WorldRoot/LivingRoom")
	var navigation := RoomNavigation.new()
	var actor_names := ["Agent", "JueAgent"]
	var waypoint_names := [
		"perimeter_w", "room_center", "sofa_seat_left", "sofa_seat_right",
		"tv_front", "stage_left", "stage_right",
	]
	for actor_name in actor_names:
		var actor := room.get_node(actor_name) as CharacterBody3D
		var navigation_agent := actor.get_node("NavigationAgent3D") as NavigationAgent3D
		var map_rid := navigation_agent.get_navigation_map()
		_assert_map_ready(map_rid, actor_name)
		for waypoint_name in waypoint_names:
			_check_path(
				map_rid, actor.global_position, navigation.get_waypoint(waypoint_name),
				"%s -> %s" % [actor_name, waypoint_name],
			)
	scene.free()
	await process_frame
	print("PARAMETRIC_NAV_WAYPOINT_%s" % ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)


## [S4.2][D2] 验证路径存在且最后一点落在目标容差内。
func _check_path(map_rid: RID, start: Vector3, target: Vector3, label: String) -> void:
	var path := NavigationServer3D.map_get_path(map_rid, start, target, true)
	if path.is_empty():
		_fail("%s empty path" % label)
		return
	var distance := path[path.size() - 1].distance_to(target)
	if distance > 0.5:
		_fail("%s endpoint miss %.2fm path=%s" % [label, distance, path])


## [S4.2] 验证角色引用的地图已同步至少一个 Region。
func _assert_map_ready(map_rid: RID, actor_name: String) -> void:
	var regions := NavigationServer3D.map_get_regions(map_rid)
	var iteration := NavigationServer3D.map_get_iteration_id(map_rid)
	var actor := current_scene.get_node("WorldRoot/LivingRoom/" + actor_name) as Node3D
	var closest := NavigationServer3D.map_get_closest_point(map_rid, actor.global_position)
	print("PARAMETRIC_NAV_ACTOR %s pos=%s closest=%s" % [
		actor_name, actor.global_position, closest,
	])
	if map_rid == RID() or regions.is_empty() or iteration < 2:
		_fail(
			"%s map unavailable rid=%s regions=%d iteration=%d"
			% [actor_name, map_rid, regions.size(), iteration]
		)


## [S4.2] 累积导航失败并保留全部诊断。
func _fail(message: String) -> void:
	_failed = true
	push_error("PARAMETRIC_NAV_WAYPOINT_FAIL: " + message)
