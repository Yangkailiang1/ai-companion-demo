# Headless acceptance for daily rhythm, resumable intentions and per-Agent reflection.

extends SceneTree

var resumed_contexts: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var bus := root.get_node("MessageBus")
	var world := root.get_node("WorldSimulator")
	var psyche := root.get_node("AgentPsycheSystem")
	var autonomy := root.get_node("AutonomousBehaviorSystem")
	var memory := root.get_node("MemorySystem")
	autonomy.set_scheduler_enabled(false)
	world.time_of_day = AffordanceTypes.TimeOfDay.MORNING

	var main_plan: Dictionary = psyche.get_daily_plan("main_agent")
	var jue_plan: Dictionary = psyche.get_daily_plan("jue_agent")
	_assert(String(main_plan.get("period", "")) == "morning", "main daily plan has the wrong period")
	_assert(String(jue_plan.get("period", "")) == "morning", "Jue daily plan has the wrong period")
	_assert(
		psyche.get_schedule_modifier("main_agent", "plant_care")
		> psyche.get_schedule_modifier("main_agent", "read_book"),
		"main morning rhythm should prioritize care over reading"
	)
	_assert(
		psyche.get_schedule_modifier("jue_agent", "read_book")
		> psyche.get_schedule_modifier("jue_agent", "wander_room"),
		"Jue morning rhythm should prioritize reading over wandering"
	)

	bus.agent_activity_started.connect(func(agent_id: String, activity_id: String, context: Dictionary):
		if agent_id == "jue_agent" and activity_id == "read_book" and bool(context.get("resumed", false)):
			resumed_contexts.append(context.duplicate(true))
	)

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

	bus.player_message_received.emit("诀，先和我说句话。", false)
	await process_frame
	await process_frame
	_assert(autonomy.get_active_activity("jue_agent").is_empty(), "player did not preempt reading")
	_assert(autonomy.get_suspended_activity("jue_agent") == "read_book", "interrupted reading was not suspended")
	_assert(
		String(psyche.get_agent_state("jue_agent").get("intention", "")) == "respond_to_player",
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
		String(psyche.get_agent_state("jue_agent").get("intention", "")) == "read_book",
		"resumed activity did not restore the character intention"
	)

	var episodes_before := (memory.agent_memories["jue_agent"]["episodes"] as Array).size()
	memory.add_episode_for_agent("jue_agent", "玩家刚才叫住我，我回应后又继续阅读。", 4.0)
	memory.request_reflection_for_agent("jue_agent")
	await process_frame
	var jue_episodes: Array = memory.agent_memories["jue_agent"]["episodes"]
	_assert(jue_episodes.size() > episodes_before, "reflection did not append a memory")
	_assert("[反思]" in String(jue_episodes[-1].get("content", "")), "latest memory is not a reflection")
	var thoughts: Array = psyche.get_agent_state("jue_agent").get("private_thoughts", [])
	_assert(
		not thoughts.is_empty() and "长期反思" in String(thoughts[-1].get("content", "")),
		"reflection did not update the private thought stream"
	)

	print("PLANNING_REFLECTION_PASS main=%s jue=%s resumed=%d reflection=%s" % [
		main_plan.get("priorities", []),
		jue_plan.get("priorities", []),
		resumed_contexts.size(),
		jue_episodes[-1].get("content", ""),
	])
	scene.free()
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("PLANNING_REFLECTION_FAIL: " + message)
	quit(1)
	assert(condition, message)


func _contains_agent_candidate(candidates: Array, agent_id: String) -> bool:
	for candidate in candidates:
		if String(candidate.get("agent_id", "")) == agent_id:
			return true
	return false
