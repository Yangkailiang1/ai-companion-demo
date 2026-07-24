# Headless acceptance for persistent psyche, attention, Theory of Mind and graph state.

extends SceneTree

var captured_cues: Array[Dictionary] = []
var captured_expressions: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var bus := root.get_node("MessageBus")
	var psyche := root.get_node("AgentPsycheSystem")
	var autonomy := root.get_node("AutonomousBehaviorSystem")
	var cognitive := root.get_node("CognitiveCycle")
	var save_system := root.get_node("SaveSystem")
	autonomy.set_scheduler_enabled(false)
	bus.performance_cue.connect(func(gesture: String, context: Dictionary):
		captured_cues.append({"gesture": gesture, "context": context.duplicate(true)})
	)
	bus.expression_cue.connect(func(expression: String, intensity: float, context: Dictionary):
		captured_expressions.append({
			"expression": expression,
			"intensity": intensity,
			"context": context.duplicate(true),
		})
	)

	var main_read_before: float = psyche.get_utility_modifier("main_agent", "read_book")
	var jue_read_before: float = psyche.get_utility_modifier("jue_agent", "read_book")
	_assert(jue_read_before > main_read_before, "Jue must have a stronger psychological reading preference")
	var main_care_before: float = psyche.get_utility_modifier("main_agent", "plant_care")
	var initial_main: Dictionary = psyche.get_agent_state("main_agent")
	var initial_jue: Dictionary = psyche.get_agent_state("jue_agent")
	_assert(
		not is_equal_approx(float(initial_main["mood"]["arousal"]), float(initial_jue["mood"]["arousal"])),
		"characters must not share the same baseline mood"
	)

	bus.player_attention_requested.emit("jue_agent", "诀，你真可爱，我们一起聊聊吧")
	await create_timer(0.4).timeout
	var attentive_jue: Dictionary = psyche.get_agent_state("jue_agent")
	_assert(String(attentive_jue.get("attention", "")) == "player", "player speech did not claim Jue's attention")
	_assert(String(attentive_jue.get("intention", "")) == "respond_to_player", "Jue did not form a response intention")
	_assert(
		float(attentive_jue["mood"]["arousal"]) > float(initial_jue["mood"]["arousal"]),
		"player attention did not change arousal"
	)
	_assert(_has_targeted_cue(captured_cues, "jue_agent", "psyche_player_attention"), "attention gesture was not targeted to Jue")
	_assert(_has_targeted_expression(captured_expressions, "jue_agent"), "attention expression was not targeted to Jue")

	bus.agent_activity_started.emit("main_agent", "plant_care", {"focus_target": "plant"})
	await process_frame
	var jue_belief: Dictionary = psyche.get_belief("jue_agent", "main_agent")
	_assert(String(jue_belief.get("observed_activity", "")) == "plant_care", "Jue did not observe main Agent activity")
	_assert("小绿" in String(jue_belief.get("inferred_intent", "")), "Jue did not infer a plant-care intention")
	_assert(float(jue_belief.get("confidence", 0.0)) > 0.5, "social belief confidence is missing")

	bus.agent_activity_completed.emit("main_agent", "plant_care", {"duration_seconds": 4.0})
	await process_frame
	var completed_main: Dictionary = psyche.get_agent_state("main_agent")
	_assert(String(completed_main.get("intention", "")) == "", "completed intention was not cleared")
	_assert("plant_care" in completed_main.get("recent_activities", []), "activity history was not updated")
	_assert(
		float(completed_main["mood"]["valence"]) > float(initial_main["mood"]["valence"]),
		"successful care did not improve mood"
	)
	var repeated_care_modifier: float = psyche.get_utility_modifier("main_agent", "plant_care")
	_assert(repeated_care_modifier < main_care_before, "habituation did not reduce immediate repetition")
	_assert((completed_main.get("private_thoughts", []) as Array).size() >= 2, "private thought stream was not recorded")

	var graph_state: Dictionary = psyche.build_graph_state("jue_agent", {"text": "你好", "source": "player"})
	_assert(String(graph_state.get("thread_id", "")) == "agent:jue_agent", "graph thread ID is not Agent-scoped")
	_assert(String(graph_state.get("agent_id", "")) == "jue_agent", "graph state has the wrong Agent")
	_assert(graph_state.get("profile", {}).has("traits"), "graph state is missing personality traits")
	_assert(graph_state.get("psyche", {}).has("beliefs"), "graph state is missing Theory-of-Mind beliefs")

	var psychology_context: String = psyche.build_cognitive_context("jue_agent")
	var prompt: String = cognitive.build_prompt(
		"[世界]",
		"[记忆]",
		"",
		psychology_context,
		[],
		"你好",
		AffordanceTypes.TriggerSource.PLAYER_INPUT,
		"jue_agent"
	)
	_assert("[持续心理状态]" in prompt, "LLM prompt does not include persistent psyche")
	_assert("可能不完全正确" in prompt, "LLM prompt treats social beliefs as ground truth")
	_assert(save_system.get_snapshot().has("psychology"), "save snapshot does not persist psychology")

	print("AGENT_PSYCHE_PASS read_main=%.3f read_jue=%.3f repeated_care=%.3f" % [
		main_read_before,
		jue_read_before,
		repeated_care_modifier,
	])
	scene.free()
	quit(0)


func _has_targeted_cue(cues: Array[Dictionary], agent_id: String, source: String) -> bool:
	for item in cues:
		var context: Dictionary = item.get("context", {})
		if String(context.get("agent_id", "")) == agent_id and String(context.get("source", "")) == source:
			return true
	return false


func _has_targeted_expression(expressions: Array[Dictionary], agent_id: String) -> bool:
	for item in expressions:
		var context: Dictionary = item.get("context", {})
		if String(context.get("agent_id", "")) == agent_id:
			return true
	return false


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("AGENT_PSYCHE_FAIL: " + message)
	quit(1)
	assert(condition, message)
