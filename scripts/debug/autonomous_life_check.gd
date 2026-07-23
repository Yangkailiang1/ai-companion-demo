# Headless acceptance: dry plant -> water -> sofa rest, social memory, player priority.
# Run with: Godot --headless --path . --script scripts/debug/autonomous_life_check.gd

extends SceneTree

var captured_actions: Array = []
var routine_completed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var bus := root.get_node("MessageBus")
	var autonomy := root.get_node("AutonomousBehaviorSystem")
	autonomy.set_scheduler_enabled(false)
	var memory := root.get_node("MemorySystem")
	var plant := scene.get_node("WorldRoot/LivingRoom/Plant")
	var plant_state := plant.get_node("PlantState")
	var main_agent: Node3D = scene.get_node("WorldRoot/LivingRoom/Agent")
	var jue_agent: Node3D = scene.get_node("WorldRoot/LivingRoom/JueAgent")

	var nav_agent := main_agent.get_node("NavigationAgent3D") as NavigationAgent3D
	var navigation_map := nav_agent.get_navigation_map()
	for _frame in range(90):
		if NavigationServer3D.map_get_iteration_id(navigation_map) >= 2:
			break
		await physics_frame
	_assert(NavigationServer3D.map_get_iteration_id(navigation_map) >= 2, "NavigationMesh did not synchronize")

	# Make the precondition deterministic even when the scene defaults change later.
	plant_state.advance_hours(3)
	var moisture_before: float = plant_state.moisture
	var respect_before: float = float(memory.retrieve_relationship_for_agent("jue_agent", "main_agent").get("respect", 0.3))

	bus.emit_actions.connect(func(agent_id: String, actions: Array):
		if agent_id == "main_agent":
			captured_actions = actions
	)
	bus.action_queue_completed.connect(func(agent_id: String):
		if agent_id == "main_agent":
			routine_completed = true
	)
	_assert(autonomy.evaluate_now(), "dry plant did not start an autonomous routine")
	_assert(autonomy.get_active_agent_id() == "main_agent", "main agent was not selected")
	_assert(captured_actions.size() == 6, "routine must contain transition plus five primitive actions")
	_assert(captured_actions[0].type == AffordanceTypes.Primitive.LOOK_AT, "routine must orient to its focus first")
	_assert(captured_actions[1].type == AffordanceTypes.Primitive.NAVIGATE, "routine must navigate after orienting")
	_assert(String(captured_actions[1].params.get("target", "")) == "plant", "first target must be plant")
	_assert(captured_actions[2].type == AffordanceTypes.Primitive.INTERACT, "third action must interact")
	_assert(String(captured_actions[2].params.get("verb", "")) == "water", "plant interaction must water")
	_assert(String(captured_actions[3].params.get("target", "")) == "sofa", "rest target must be sofa")
	_assert(captured_actions[4].type == AffordanceTypes.Primitive.SIT, "routine must sit after navigation")

	var started_at := Time.get_ticks_msec()
	while not routine_completed and Time.get_ticks_msec() - started_at < 15000:
		await physics_frame
	_assert(routine_completed, "autonomous queue did not report completion")
	_assert(main_agent.current_activity == "idle", "autonomous queue did not terminate")
	_assert(plant_state.moisture > moisture_before, "watering did not increase plant moisture")
	var sofa = root.get_node("SemanticWorld").get_object("sofa")
	_assert(main_agent.global_position.distance_to(sofa.interaction_point) <= 0.8, "agent did not finish near sofa")
	_assert(autonomy.get_active_agent_id().is_empty(), "autonomous ownership was not released")

	var main_memories: Array = memory.retrieve_relevant_for_agent("main_agent", "小绿 浇水", 10)
	var jue_memories: Array = memory.retrieve_relevant_for_agent("jue_agent", "小绿 照顾", 10)
	_assert(_contains_episode(main_memories, "主动浇"), "main agent did not remember the completed routine")
	_assert(_contains_episode(jue_memories, "照顾缺水"), "companion did not remember the social observation")
	var relationship: Dictionary = memory.retrieve_relationship_for_agent("jue_agent", "main_agent")
	_assert(float(relationship.get("respect", 0.0)) > respect_before, "companion respect did not change")

	# A player's interaction claims priority immediately, even during an autonomous queue.
	bus.player_message_received.emit("测试准备", false)
	await process_frame
	autonomy._last_player_input_msec = -10000
	autonomy._agent_available_after_msec.clear()
	autonomy._activity_last_started.clear()
	autonomy._last_global_start_msec = -2000
	plant_state.advance_hours(12)
	routine_completed = false
	_assert(autonomy.evaluate_now(), "second routine did not start for interruption test")
	bus.player_message_received.emit("先和我说话", false)
	await process_frame
	_assert(autonomy.get_active_agent_id().is_empty(), "player input did not preempt autonomous ownership")
	_assert(main_agent.current_activity == "idle", "player input did not stop the autonomous action queue")

	print("AUTONOMOUS_LIFE_PASS moisture=%.1f main=%s jue=%s" % [
		plant_state.moisture,
		main_agent.global_position,
		jue_agent.global_position,
	])
	scene.free()
	quit(0)


func _contains_episode(episodes: Array, needle: String) -> bool:
	for entry in episodes:
		if needle in String(entry.get("content", "")):
			return true
	return false


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("AUTONOMOUS_LIFE_FAIL: " + message)
	quit(1)
	assert(condition, message)
