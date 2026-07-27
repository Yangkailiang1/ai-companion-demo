# Headless acceptance: dry plant -> water -> sofa rest, social memory, player priority.
# Run with: Godot --headless --path . --script scripts/debug/autonomous_life_check.gd
# Verifies: C9.1, C9.2, T4.5

extends SceneTree

var captured_actions: Array = []
var routine_completed := false
var failed := false


## [T4.5] Starts the asynchronous autonomous-life acceptance flow.
func _init() -> void:
	call_deferred("_run")


## [C9.1][C9.2][T4.5] Composes navigation, routine, memory and preemption checks.
func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var context := _build_context(scene)
	await _wait_for_navigation(context.main_agent)
	var baseline := _prepare_routine_fixture(context)
	_connect_activity_capture(context.bus)
	_verify_routine_start(context.autonomy)
	await _verify_routine_outcome(context, baseline)
	await _verify_player_preemption(context)

	print("AUTONOMOUS_LIFE_PASS moisture=%.1f main=%s jue=%s" % [
		context.plant_state.moisture,
		context.main_agent.global_position,
		context.jue_agent.global_position,
	])
	scene.free()
	quit(1 if failed else 0)


## [C9.1] Resolves the scene services and actors used by the behavior contract.
func _build_context(scene: Node) -> Dictionary:
	return {
		"bus": root.get_node("MessageBus"),
		"autonomy": root.get_node("AutonomousBehaviorSystem"),
		"memory": root.get_node("MemorySystem"),
		"plant_state": scene.get_node("WorldRoot/LivingRoom/Plant/PlantState"),
		"main_agent": scene.get_node("WorldRoot/LivingRoom/Agent"),
		"jue_agent": scene.get_node("WorldRoot/LivingRoom/JueAgent"),
	}


## [C9.1] Waits until the room navigation map can accept locomotion requests.
func _wait_for_navigation(main_agent: Node3D) -> void:
	var nav_agent := main_agent.get_node("NavigationAgent3D") as NavigationAgent3D
	var navigation_map := nav_agent.get_navigation_map()
	for _frame in range(90):
		if NavigationServer3D.map_get_iteration_id(navigation_map) >= 2:
			break
		await physics_frame
	_assert(NavigationServer3D.map_get_iteration_id(navigation_map) >= 2, "NavigationMesh did not synchronize")


## [C9.1][T4.5] Establishes a dry plant and deterministic Agent eligibility.
func _prepare_routine_fixture(context: Dictionary) -> Dictionary:
	var autonomy: Node = context.autonomy
	var plant_state: Node = context.plant_state
	autonomy.set_scheduler_enabled(false)
	plant_state.moisture = 8.0
	plant_state.health = 70.0
	plant_state._sync_state()
	autonomy._agent_available_after_msec["jue_agent"] = Time.get_ticks_msec() + 30000
	for activity_id in ["read_book", "rest_on_sofa", "wander_room"]:
		autonomy._activity_last_started["main_agent:%s" % activity_id] = Time.get_ticks_msec()
	return {
		"moisture": plant_state.moisture,
		"respect": float(context.memory.retrieve_relationship_for_agent(
			"jue_agent", "main_agent").get("respect", 0.3)),
	}


## [C9.1] Captures the main Agent action queue and completion signal.
func _connect_activity_capture(bus: Node) -> void:
	bus.emit_actions.connect(func(agent_id: String, actions: Array):
		if agent_id == "main_agent":
			captured_actions = actions
	)
	bus.action_queue_completed.connect(func(agent_id: String):
		if agent_id == "main_agent":
			routine_completed = true
	)


## [C9.1] Verifies that dry-plant selection compiles into the expected primitive queue.
func _verify_routine_start(autonomy: Node) -> void:
	_assert(autonomy.evaluate_now(), "dry plant did not start an autonomous routine")
	_assert(autonomy.get_active_agent_id() == "main_agent", "main agent was not selected")
	_assert(captured_actions.size() == 6, "routine must contain transition plus five primitive actions")
	if captured_actions.size() < 5:
		return
	_assert(captured_actions[0].type == AffordanceTypes.Primitive.LOOK_AT, "routine must orient to its focus first")
	_assert(captured_actions[1].type == AffordanceTypes.Primitive.NAVIGATE, "routine must navigate after orienting")
	_assert(String(captured_actions[1].params.get("target", "")) == "plant", "first target must be plant")
	_assert(captured_actions[2].type == AffordanceTypes.Primitive.INTERACT, "third action must interact")
	_assert(String(captured_actions[2].params.get("verb", "")) == "water", "plant interaction must water")
	_assert(String(captured_actions[3].params.get("target", "")) == "sofa", "rest target must be sofa")
	_assert(captured_actions[4].type == AffordanceTypes.Primitive.SIT, "routine must sit after navigation")


## [C9.1][C9.2] Verifies world effects, resource release, memory and social observation.
func _verify_routine_outcome(context: Dictionary, baseline: Dictionary) -> void:
	var started_at := Time.get_ticks_msec()
	while not routine_completed and Time.get_ticks_msec() - started_at < 15000:
		await physics_frame
	_assert(routine_completed, "autonomous queue did not report completion")
	_assert(context.main_agent.current_activity == "idle", "autonomous queue did not terminate")
	_assert(context.plant_state.moisture > baseline.moisture, "watering did not increase plant moisture")
	var sofa = root.get_node("SemanticWorld").get_object("sofa")
	_assert(context.main_agent.global_position.distance_to(sofa.interaction_point) <= 0.8, "agent did not finish near sofa")
	_assert(context.autonomy.get_active_agent_id().is_empty(), "autonomous ownership was not released")
	var main_memories: Array = context.memory.retrieve_relevant_for_agent("main_agent", "小绿 浇水", 10)
	var jue_memories: Array = context.memory.retrieve_relevant_for_agent("jue_agent", "小绿 照顾", 10)
	_assert(_contains_episode(main_memories, "主动浇"), "main agent did not remember the completed routine")
	_assert(_contains_episode(jue_memories, "照顾缺水"), "companion did not remember the social observation")
	var relationship: Dictionary = context.memory.retrieve_relationship_for_agent("jue_agent", "main_agent")
	_assert(float(relationship.get("respect", 0.0)) > baseline.respect, "companion respect did not change")



## [C9.2] Verifies that direct player interaction preempts an autonomous queue.
func _verify_player_preemption(context: Dictionary) -> void:
	var autonomy: Node = context.autonomy
	context.bus.player_message_received.emit("测试准备", false)
	await process_frame
	autonomy._last_player_input_msec = -10000
	autonomy._agent_available_after_msec.clear()
	autonomy._activity_last_started.clear()
	autonomy._last_global_start_msec = -2000
	context.plant_state.advance_hours(12)
	routine_completed = false
	_assert(autonomy.evaluate_now(), "second routine did not start for interruption test")
	context.bus.player_message_received.emit("先和我说话", false)
	await process_frame
	_assert(autonomy.get_active_agent_id().is_empty(), "player input did not preempt autonomous ownership")
	_assert(context.main_agent.current_activity == "idle", "player input did not stop the autonomous action queue")


## [C9.2] Searches episodic records for a completed or observed activity.
func _contains_episode(episodes: Array, needle: String) -> bool:
	for entry in episodes:
		if needle in String(entry.get("content", "")):
			return true
	return false


## [T4.5] Records a stable failure while allowing cleanup to complete.
func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	failed = true
	push_error("AUTONOMOUS_LIFE_FAIL: " + message)
