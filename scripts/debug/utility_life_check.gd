# Headless acceptance: personality-weighted Utility AI, resource locks and diagnostics.

extends SceneTree

var captured_agent_id := ""
var captured_actions: Array = []
var completed_agents: Array[String] = []


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
	var memory := root.get_node("MemorySystem")
	var world_simulator := root.get_node("WorldSimulator")
	var plant_state := scene.get_node("WorldRoot/LivingRoom/Plant/PlantState")
	autonomy.set_scheduler_enabled(false)
	plant_state.perform_interaction("water", "test")
	world_simulator.get_needs_for_agent("main_agent").fun = 90.0
	world_simulator.get_needs_for_agent("main_agent").energy = 100.0
	world_simulator.get_needs_for_agent("jue_agent").fun = 35.0
	world_simulator.get_needs_for_agent("jue_agent").energy = 80.0

	bus.emit_actions.connect(func(agent_id: String, actions: Array):
		if not actions.is_empty():
			captured_agent_id = agent_id
			captured_actions = actions
	)
	bus.action_queue_completed.connect(func(agent_id: String):
		completed_agents.append(agent_id)
	)

	_assert(autonomy.evaluate_now(), "Utility AI did not select an activity")
	var diagnostics: Dictionary = autonomy.get_diagnostics()
	var selected: Dictionary = diagnostics.get("selected", {})
	_assert(String(selected.get("agent_id", "")) == "jue_agent", "Jue should win the reading preference")
	_assert(String(selected.get("activity_id", "")) == "read_book", "low fun should select reading")
	_assert(captured_agent_id == "jue_agent", "selected activity was routed to the wrong Agent")
	_assert(captured_actions[0].type == AffordanceTypes.Primitive.LOOK_AT, "activity lacks orientation transition")
	_assert(autonomy.get_active_activity("jue_agent") == "read_book", "active activity was not tracked")
	_assert(String(autonomy._resource_owners.get("book", "")) == "jue_agent", "book was not reserved")

	# Allow another decision while Jue is still reading; the book lock must prevent
	# a second Agent from selecting the same resource.
	autonomy._last_global_start_msec = -2000
	autonomy.evaluate_now()
	var second_selected: Dictionary = autonomy.get_diagnostics().get("selected", {})
	_assert(
		String(second_selected.get("activity_id", "")) == "wander_room",
		"second Agent should choose unreserved wandering, got %s score=%s" % [
			second_selected.get("activity_id", ""),
			second_selected.get("score", ""),
		]
	)
	_assert(
		not (String(second_selected.get("activity_id", "")) == "read_book"
			and String(second_selected.get("agent_id", "")) != "jue_agent"),
		"reserved book was assigned to another Agent"
	)

	var started_at := Time.get_ticks_msec()
	while "jue_agent" not in completed_agents and Time.get_ticks_msec() - started_at < 12000:
		await physics_frame
	_assert("jue_agent" in completed_agents, "reading queue did not complete")
	_assert(not autonomy._resource_owners.has("book"), "book reservation was not released")
	_assert(world_simulator.get_needs_for_agent("jue_agent").fun > 35.0, "reading did not restore Jue's fun")
	var main_fun_after: float = world_simulator.get_needs_for_agent("main_agent").fun
	_assert(is_equal_approx(main_fun_after, 90.0), "Jue's activity changed the main Agent's needs: %.1f" % main_fun_after)
	var episodes: Array = memory.retrieve_relevant_for_agent("jue_agent", "读书 故事", 10)
	_assert(_contains_episode(episodes, "故事的新进展"), "reading outcome was not written to Jue memory")

	# With every activity cooling down, an idle Agent should perform a contextual,
	# silent micro behavior instead of producing dialogue spam.
	bus.player_message_received.emit("测试准备", false)
	await process_frame
	autonomy._last_player_input_msec = -10000
	autonomy._active_activities.clear()
	autonomy._resource_owners.clear()
	autonomy._agent_available_after_msec.clear()
	for agent in ["main_agent", "jue_agent"]:
		for activity in ["plant_care", "read_book", "rest_on_sofa", "wander_room"]:
			autonomy._activity_last_started["%s:%s" % [agent, activity]] = Time.get_ticks_msec()
	autonomy._last_global_start_msec = -2000
	_assert(not autonomy.evaluate_now(), "cooling activities should not start")
	_assert(String(autonomy.get_diagnostics().get("status", "")) == "micro_behavior", "idle gap did not produce a micro behavior")

	print("UTILITY_LIFE_PASS selected=%s activity=%s candidates=%d" % [
		selected.get("agent_id", ""),
		selected.get("activity_id", ""),
		(diagnostics.get("candidates", []) as Array).size(),
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
	push_error("UTILITY_LIFE_FAIL: " + message)
	quit(1)
	assert(condition, message)
