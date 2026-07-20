# Headless v0.3 acceptance: route data, plan safety, Chinese intent, and real movement.
# Run with: Godot --headless --path . --script scripts/debug/spatial_autonomy_check.gd

extends SceneTree

var captured_actions: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var bus := root.get_node("MessageBus")
	var cognitive := root.get_node("CognitiveCycle")
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var pending_agent := scene.find_child("Agent", true, false)
	var pending_nav_agent := pending_agent.get_node("NavigationAgent3D") as NavigationAgent3D
	var pending_map := pending_nav_agent.get_navigation_map()
	for _frame in range(60):
		if NavigationServer3D.map_get_iteration_id(pending_map) >= 2:
			break
		await physics_frame
	_assert(NavigationServer3D.map_get_iteration_id(pending_map) >= 2, "NavigationMesh did not synchronize")

	var navigation := RoomNavigation.new()
	var route := navigation.get_route("room_perimeter", 1)
	_assert(route.size() >= 9, "patrol route must contain a closed multi-point lap")
	_assert(route[0].is_equal_approx(route[-1]), "patrol route must close at its first point")
	var unique: Dictionary = {}
	for point in route:
		_assert(navigation.is_safe_position(point), "route point outside safe bounds: %s" % point)
		unique[str(point)] = true
	_assert(unique.size() >= 8, "patrol route must contain distinct targets")
	_assert(navigation.is_safe_position(navigation.get_wander_point(0)), "wander point is unsafe")

	var validator := PlanValidator.new()
	var valid_plan := validator.compile([
		{"action": "navigate_waypoint", "waypoint": "room_center"},
		{"action": "look_at", "target": "tv"},
		{"action": "wait", "duration": 0.2},
	])
	_assert(valid_plan.size() == 3, "valid structured plan was rejected")
	_assert(validator.compile([{"action": "navigate_waypoint", "waypoint": "outside"}]).is_empty(), "unknown waypoint was accepted")
	_assert(validator.compile([{"action": "shell", "command": "bad"}]).is_empty(), "unknown action was accepted")

	# Deterministic local cognition: verify Chinese patrol intent without executing it.
	cognitive.llm_api_url = ""
	cognitive.llm_api_key = ""
	var agent := scene.find_child("Agent", true, false)
	var nav_agent := agent.get_node("NavigationAgent3D") as NavigationAgent3D
	var navigation_map := nav_agent.get_navigation_map()
	_assert(NavigationServer3D.map_get_regions(navigation_map).size() > 0, "room NavigationRegion3D is not registered")
	for point in route:
		var path := NavigationServer3D.map_get_path(navigation_map, agent.global_position, point, true)
		_assert(path.size() >= 2, "route waypoint is unreachable on NavigationMesh: %s" % point)
	var handler := Callable(agent, "_on_emit_actions")
	if bus.emit_actions.is_connected(handler):
		bus.emit_actions.disconnect(handler)
	bus.emit_actions.connect(func(_agent_id: String, actions: Array): captured_actions = actions)
	bus.route_player_input("请绕着整个房间转一圈")
	await process_frame
	_assert(captured_actions.size() == 1, "patrol intent did not emit exactly one primitive")
	_assert(captured_actions[0].type == AffordanceTypes.Primitive.PATROL, "patrol intent emitted wrong primitive")

	# Real physics movement and animation state.
	var start: Vector3 = agent.global_position
	var player := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	agent.move_to_position(navigation.get_waypoint("perimeter_nw"))
	await physics_frame
	_assert(player.current_animation == "walk", "walk animation did not start during movement")
	for _frame in range(30):
		await physics_frame
	_assert(agent.global_position.distance_to(start) > 0.5, "agent did not change world position")
	var movement_direction: Vector3 = (agent.global_position - start).normalized()
	var visual_forward: Vector3 = agent.global_transform.basis.z.normalized()
	_assert(visual_forward.dot(movement_direction) > 0.7, "penguin visual forward axis points away from movement")
	agent.cancel_movement("test_complete")
	_assert(not agent.is_moving, "movement cancellation did not terminate")

	# Execute the complete closed lap and ensure its asynchronous queue terminates.
	agent._on_emit_actions("main_agent", captured_actions)
	var patrol_started_at := Time.get_ticks_msec()
	while agent.current_activity != "idle" and Time.get_ticks_msec() - patrol_started_at < 20000:
		await physics_frame
	_assert(agent.current_activity == "idle", "patrol action queue did not terminate")
	_assert(agent.global_position.distance_to(route[0]) <= 0.8, "patrol did not finish at the closed route origin")
	_assert(player.current_animation == "idle", "patrol did not return to idle animation")

	print("SPATIAL_AUTONOMY_PASS route_points=", route.size(), " unique=", unique.size(), " final=", agent.global_position)
	scene.free()
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("SPATIAL_AUTONOMY_FAIL: " + message)
	quit(1)
