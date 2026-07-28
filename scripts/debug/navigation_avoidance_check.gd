# Verifies: C4.1
# Covers: avoidance enabled → intersecting paths → safe separation →
#   no obstacle penetration → arrival within timeout → cancellation zeroes velocity
extends SceneTree

var _failed := false
var _main_arrived := false
var _jue_arrived := false
var _min_separation := INF
var _main_trace: Array[Vector3] = []
var _jue_trace: Array[Vector3] = []
var _obstacles: Array[Dictionary] = []
var _minimum_clearance_meters: float = 0.6


## [T4.5] Starts the avoidance acceptance flow.
func _init() -> void:
	call_deferred("_run")


## [C4.1] Loads living room, verifies avoidance setup, runs intersecting path test
## and cancellation contract.
func _run() -> void:
	root.get_node("ExperienceModeManager").enter_performance_mode()
	var room: Node = await _load_room()
	await _wait_for_navigation(room)
	_verify_avoidance_enabled(room)
	if _failed:
		room.queue_free()
		await process_frame
		quit(1)
		return
	_load_obstacles()
	await _run_intersecting_paths(room)
	_verify_separation_and_obstacles()
	await _verify_cancellation(room)
	if not _failed:
		_report_pass()
	room.queue_free()
	await process_frame
	quit(1 if _failed else 0)


## [C4.1] Instantiates the living room scene.
func _load_room() -> Node:
	var packed := load("res://scenes/living_room.tscn") as PackedScene
	var room := packed.instantiate()
	root.add_child(room)
	await process_frame
	await process_frame
	return room


## [C4.1] Waits until the NavigationMesh is baked and fully synchronized.
func _wait_for_navigation(room: Node) -> void:
	var main_agent := room.get_node("Agent")
	var nav_agent := main_agent.get_node("NavigationAgent3D") as NavigationAgent3D
	var navigation_map := nav_agent.get_navigation_map()
	for _frame in range(90):
		if NavigationServer3D.map_get_iteration_id(navigation_map) >= 2:
			break
		await physics_frame
	_assert(NavigationServer3D.map_get_iteration_id(navigation_map) >= 2, "NavigationMesh did not synchronize")
	_assert(
		NavigationServer3D.map_get_regions(navigation_map).size() > 0,
		"room NavigationRegion3D is not registered",
	)


## [C4.1] Confirms _avoidance_enabled is true on main, jue and any spawned
## local character.
func _verify_avoidance_enabled(room: Node) -> void:
	var main_agent := room.get_node("Agent")
	var jue_agent := room.get_node("JueAgent")
	if not main_agent.has_method("move_to_position") or not jue_agent.has_method("move_to_position"):
		_assert(false, "agent_base.gd failed to load or lacks navigation API")
		return
	for actor in get_nodes_in_group("agents"):
		actor._check_navmesh()
	_assert(main_agent._avoidance_enabled, "main agent avoidance must be enabled")
	_assert(jue_agent._avoidance_enabled, "jue agent avoidance must be enabled")
	_assert(main_agent._navmesh_ready, "main agent NavMesh must be ready")
	_assert(jue_agent._navmesh_ready, "jue agent NavMesh must be ready")
	var main_nav := main_agent.get_node("NavigationAgent3D") as NavigationAgent3D
	var jue_nav := jue_agent.get_node("NavigationAgent3D") as NavigationAgent3D
	var script_constants: Dictionary = main_agent.get_script().get_script_constant_map()
	_minimum_clearance_meters = float(
		script_constants.get("SOCIAL_CLEARANCE_METERS", _minimum_clearance_meters)
	)
	_assert(main_nav.avoidance_enabled, "main NavigationAgent3D avoidance_enabled must be true")
	_assert(jue_nav.avoidance_enabled, "jue NavigationAgent3D avoidance_enabled must be true")
	for actor in get_nodes_in_group("agents"):
		_assert(bool(actor.get("_avoidance_enabled")),
			"agent '%s' avoidance must be enabled" % String(actor.get("agent_name")))


## [C4.1] Loads obstacle definitions from scene_config.json.
func _load_obstacles() -> void:
	var navigation := RoomNavigation.new()
	_obstacles = navigation.obstacles.duplicate()


## [C4.1] Sends main and jue agents on intersecting paths, records separation
## and arrival signals. Delegates completion verification to _verify_path_completion.
func _run_intersecting_paths(room: Node) -> void:
	var main_agent := room.get_node("Agent")
	var jue_agent := room.get_node("JueAgent")
	var navigation := RoomNavigation.new()

	var main_start := navigation.get_waypoint("perimeter_w")
	var jue_start := navigation.get_waypoint("perimeter_e")
	var main_target := jue_start
	var jue_target := main_start
	main_agent.global_position = main_start
	jue_agent.global_position = jue_start
	for actor in get_nodes_in_group("agents"):
		if actor != main_agent and actor != jue_agent:
			actor.get_node("NavigationAgent3D").avoidance_enabled = false
	await physics_frame
	await physics_frame

	main_agent.arrived.connect(func(): _main_arrived = true)
	jue_agent.arrived.connect(func(): _jue_arrived = true)

	main_agent.move_to_position(main_target)
	jue_agent.move_to_position(jue_target)
	_assert(absf(main_agent.navigation_agent.avoidance_priority
		- jue_agent.navigation_agent.avoidance_priority) > 0.001,
		"moving agents must use different avoidance priorities")

	_assert(main_agent.is_moving, "main agent did not start moving")
	_assert(jue_agent.is_moving, "jue agent did not start moving")

	var started_at := Time.get_ticks_msec()
	var both_arrived := false
	var timed_out := false
	const INTERSECT_TIMEOUT_MSEC := 15000

	while not both_arrived and not timed_out:
		await physics_frame
		if _main_arrived and _jue_arrived:
			both_arrived = true
		timed_out = Time.get_ticks_msec() - started_at > INTERSECT_TIMEOUT_MSEC
		var sep: float = main_agent.global_position.distance_to(jue_agent.global_position)
		if sep < _min_separation:
			_min_separation = sep
		if Engine.get_process_frames() % 6 == 0:
			_main_trace.append(main_agent.global_position)
			_jue_trace.append(jue_agent.global_position)

	if not both_arrived:
		main_agent.cancel_movement("test_timeout")
		jue_agent.cancel_movement("test_timeout")

	await physics_frame
	await physics_frame

	_verify_path_completion(main_agent, jue_agent, main_target, jue_target, both_arrived, timed_out)


## [C4.1] Verifies both agents arrived near their targets or provides a stable
## failure reason on timeout.
func _verify_path_completion(main_agent: Node3D, jue_agent: Node3D,
		main_target: Vector3, jue_target: Vector3, both_arrived: bool, timed_out: bool) -> void:
	if both_arrived:
		var main_ok := main_agent.global_position.distance_to(main_target) <= 0.8
		var jue_ok := jue_agent.global_position.distance_to(jue_target) <= 0.8
		_assert(main_ok, "main target miss: %.3fm" % main_agent.global_position.distance_to(main_target))
		_assert(jue_ok, "jue target miss: %.3fm" % jue_agent.global_position.distance_to(jue_target))
	elif timed_out:
		_assert(false, "intersecting paths timed out — possible avoidance deadlock")
	else:
		_assert(false, "intersecting paths finished unexpectedly")


## [C4.1] Asserts minimum separation meets social clearance and neither trace
## crosses a configured obstacle.
func _verify_separation_and_obstacles() -> void:
	_assert(
		_min_separation >= _minimum_clearance_meters,
		"minimum separation is too low: min_sep=%.3f clearance=%.3f"
			% [_min_separation, _minimum_clearance_meters],
	)
	for pos in _main_trace:
		_assert(not _inside_obstacle(pos), "main agent trace crossed an obstacle at %s" % pos)
	for pos in _jue_trace:
		_assert(not _inside_obstacle(pos), "jue agent trace crossed an obstacle at %s" % pos)


## [C4.1] Checks whether a world position falls inside any configured obstacle.
func _inside_obstacle(pos: Vector3) -> bool:
	for obstacle in _obstacles:
		var obs_min: Vector3 = obstacle["min"]
		var obs_max: Vector3 = obstacle["max"]
		if pos.x >= obs_min.x and pos.x <= obs_max.x \
			and pos.z >= obs_min.z and pos.z <= obs_max.z:
			return true
	return false


## [C4.1] Starts movement, cancels mid-way, and verifies zero velocity + idle state.
func _verify_cancellation(room: Node) -> void:
	var main_agent := room.get_node("Agent")
	var navigation := RoomNavigation.new()

	main_agent.move_to_position(navigation.get_waypoint("perimeter_nw"))
	_assert(main_agent.is_moving, "movement did not start for cancellation test")
	await physics_frame
	await physics_frame
	_assert(main_agent.is_moving, "movement should still be active before cancellation")

	main_agent.cancel_movement("test_cancellation")
	await physics_frame
	await physics_frame

	_assert(not main_agent.is_moving, "movement was not terminated after cancellation")
	_assert(not main_agent.has_target, "target was not cleared after cancellation")
	_assert(main_agent.velocity.length() < 0.01, "velocity was not zeroed after cancellation")
	_assert(main_agent.current_activity == "idle" or main_agent.current_activity == "executing_actions",
		"activity not in valid post-cancellation state")

	main_agent._navmesh_ready = false
	main_agent.move_to_position(navigation.get_waypoint("perimeter_s"))
	await physics_frame
	await physics_frame
	main_agent.cancel_movement("test_direct_cancellation")
	await physics_frame
	await physics_frame

	_assert(not main_agent.is_moving, "direct fallback movement not terminated after cancellation")
	_assert(main_agent.velocity.length() < 0.01, "direct fallback velocity not zeroed after cancellation")
	main_agent._navmesh_ready = true  # Restore for cleanup.


## [T4.5] Prints the final pass message with diagnostic data.
func _report_pass() -> void:
	print(
		"NAVIGATION_AVOIDANCE_PASS main_arrived=%s jue_arrived=%s min_sep=%.3f trace_pts=%d"
		% [str(_main_arrived), str(_jue_arrived), _min_separation, _main_trace.size() + _jue_trace.size()]
	)


## [T4.5] Records a stable failure while allowing cleanup to complete.
func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("NAVIGATION_AVOIDANCE_FAIL: " + message)
