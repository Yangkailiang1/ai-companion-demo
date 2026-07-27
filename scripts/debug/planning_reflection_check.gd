# Headless acceptance for daily rhythm, resumable intentions and per-Agent reflection.
# Verifies: C9.2, C9.3, T4.5

extends SceneTree

var resumed_contexts: Array[Dictionary] = []
var failed := false


## [T4.5] Starts the asynchronous planning and reflection acceptance flow.
func _init() -> void:
	call_deferred("_run")


## [C9.2][C9.3][T4.5] Composes rhythm, interruption, resumption and reflection checks.
func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var context := _build_context()
	var plans := _verify_daily_rhythm(context)
	_connect_resume_capture(context.bus)
	await _verify_interrupt_and_resume(context)
	var reflection := await _verify_reflection(context)

	print("PLANNING_REFLECTION_PASS main=%s jue=%s resumed=%d reflection=%s" % [
		plans.main.get("priorities", []),
		plans.jue.get("priorities", []),
		resumed_contexts.size(),
		reflection,
	])
	scene.free()
	quit(1 if failed else 0)


## [C9.2] Resolves and configures the services used by this contract.
func _build_context() -> Dictionary:
	var context := {
		"bus": root.get_node("MessageBus"),
		"world": root.get_node("WorldSimulator"),
		"psyche": root.get_node("AgentPsycheSystem"),
		"autonomy": root.get_node("AutonomousBehaviorSystem"),
		"memory": root.get_node("MemorySystem"),
	}
	context.autonomy.set_scheduler_enabled(false)
	context.world.time_of_day = AffordanceTypes.TimeOfDay.MORNING
	return context


## [C9.2] Verifies personality-specific morning priorities.
func _verify_daily_rhythm(context: Dictionary) -> Dictionary:
	var main_plan: Dictionary = context.psyche.get_daily_plan("main_agent")
	var jue_plan: Dictionary = context.psyche.get_daily_plan("jue_agent")
	_assert(String(main_plan.get("period", "")) == "morning", "main daily plan has the wrong period")
	_assert(String(jue_plan.get("period", "")) == "morning", "Jue daily plan has the wrong period")
	_assert(
		context.psyche.get_schedule_modifier("main_agent", "plant_care")
		> context.psyche.get_schedule_modifier("main_agent", "read_book"),
		"main morning rhythm should prioritize care over reading"
	)
	_assert(
		context.psyche.get_schedule_modifier("jue_agent", "read_book")
		> context.psyche.get_schedule_modifier("jue_agent", "wander_room"),
		"Jue morning rhythm should prioritize reading over wandering"
	)
	return {"main": main_plan, "jue": jue_plan}


## [C9.2] Captures resumed activity context for contract verification.
func _connect_resume_capture(bus: Node) -> void:
	bus.agent_activity_started.connect(func(agent_id: String, activity_id: String, context: Dictionary):
		if agent_id == "jue_agent" and activity_id == "read_book" and bool(context.get("resumed", false)):
			resumed_contexts.append(context.duplicate(true))
	)


## [C9.2] Verifies player preemption and exact intention resumption.
func _verify_interrupt_and_resume(context: Dictionary) -> void:
	var autonomy: Node = context.autonomy
	var read_definition: Dictionary = {}
	for definition_value in autonomy._activities:
		var definition: Dictionary = definition_value
		if String(definition.get("id", "")) == "read_book":
			read_definition = definition
			break
	_assert(not read_definition.is_empty(), "read activity definition is missing")
	_assert(autonomy._start_activity({
		"agent_id": "jue_agent",
		"activity_id": "read_book",
		"score": 1.0,
		"definition": read_definition,
	}), "Jue reading activity did not start")
	await process_frame
	_assert(autonomy.get_active_activity("jue_agent") == "read_book", "reading was not active before interruption")

	context.bus.player_message_received.emit("诀，先和我说句话。", false)
	await process_frame
	await process_frame
	_assert(autonomy.get_active_activity("jue_agent").is_empty(), "player did not preempt reading")
	_assert(autonomy.get_suspended_activity("jue_agent") == "read_book", "interrupted reading was not suspended")
	_assert(
		String(context.psyche.get_agent_state("jue_agent").get("intention", "")) == "respond_to_player",
		"interrupted character did not switch intention to player response"
	)
	_assert(
		not _contains_agent_candidate(autonomy._score_candidates(), "jue_agent"),
		"suspended character received a competing autonomous task"
	)

	autonomy._last_player_input_msec = -10000
	_assert(autonomy.resume_suspended_now("jue_agent"), "Jue did not resume reading after player grace")
	await process_frame
	_assert(autonomy.get_active_activity("jue_agent") == "read_book", "resumed reading is not active")
	_assert(autonomy.get_suspended_activity("jue_agent").is_empty(), "suspended record was not consumed")
	_assert(resumed_contexts.size() == 1, "resumed activity did not expose resumed=true context")
	_assert(
		String(context.psyche.get_agent_state("jue_agent").get("intention", "")) == "read_book",
		"resumed activity did not restore the character intention"
	)


## [C9.3][T4.5] Verifies reflection by content, independent of a full 500-entry ring buffer.
func _verify_reflection(context: Dictionary) -> String:
	context.memory.add_episode_for_agent("jue_agent", "玩家刚才叫住我，我回应后又继续阅读。", 4.0)
	context.memory.request_reflection_for_agent("jue_agent")
	await process_frame
	var jue_episodes: Array = context.memory.agent_memories["jue_agent"]["episodes"]
	_assert(not jue_episodes.is_empty(), "reflection left episodic memory empty")
	_assert("[反思]" in String(jue_episodes[-1].get("content", "")), "latest memory is not a reflection")
	var thoughts: Array = context.psyche.get_agent_state("jue_agent").get("private_thoughts", [])
	_assert(
		not thoughts.is_empty() and "长期反思" in String(thoughts[-1].get("content", "")),
		"reflection did not update the private thought stream"
	)
	return String(jue_episodes[-1].get("content", ""))


## [T4.5] Records a stable failure while preserving test cleanup.
func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	failed = true
	push_error("PLANNING_REFLECTION_FAIL: " + message)


## [C9.2] Detects whether a suspended Agent leaked into candidate selection.
func _contains_agent_candidate(candidates: Array, agent_id: String) -> bool:
	for candidate in candidates:
		if String(candidate.get("agent_id", "")) == agent_id:
			return true
	return false
