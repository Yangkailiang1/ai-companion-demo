# End-to-end local-mode acceptance check for player text → cognition → gesture → animation.
# Run with: Godot --headless --path . --script scripts/debug/gesture_pipeline_check.gd

extends SceneTree

var received_cues: Array[String] = []
var received_lines: Array[String] = []
var emitted_targets: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var bus := root.get_node("MessageBus")
	var cognitive := root.get_node("CognitiveCycle")
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	# Capture planned actions without executing their timers/movement; execution is
	# covered by the startup scene check and would outlive this short test process.
	var agent := main.find_child("Agent", true, false)
	var agent_action_handler := Callable(agent, "_on_emit_actions")
	if bus.emit_actions.is_connected(agent_action_handler):
		bus.emit_actions.disconnect(agent_action_handler)
	# Exercise deterministic local rules without reading or changing config files.
	cognitive.llm_api_url = ""
	cognitive.llm_api_key = ""
	bus.performance_cue.connect(func(gesture: String, _context: Dictionary): received_cues.append(gesture))
	bus.ui_add_chat_entry.connect(func(_speaker: String, text: String, is_player: bool):
		if not is_player:
			received_lines.append(text)
	)
	bus.emit_actions.connect(_capture_actions)
	var player := main.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null:
		_fail("AnimationPlayer not found")
		return

	var gesture_cases := {
		"请挥挥手": "wave",
		"请点点头": "nod",
		"先想一想": "think",
		"开心一点": "happy",
	}
	for input_text in gesture_cases:
		received_cues.clear()
		bus.route_player_input(input_text)
		await process_frame
		var expected: String = gesture_cases[input_text]
		if expected not in received_cues:
			_fail("%s did not emit %s: %s" % [input_text, expected, received_cues])
			return
		if player.current_animation != expected:
			_fail("%s did not play %s (playing %s)" % [input_text, expected, player.current_animation])
			return

	received_lines.clear()
	emitted_targets.clear()
	bus.route_player_input("我们一起去看电视吗？")
	await process_frame
	if received_lines.is_empty() or "电视" not in received_lines[-1]:
		_fail("TV request received an irrelevant response: %s" % received_lines)
		return
	if "tv" not in emitted_targets:
		_fail("TV request did not plan an action targeting tv: %s" % emitted_targets)
		return
	print("GESTURE_PIPELINE_PASS cues=wave,nod,think,happy tv_response=", received_lines[-1])
	main.free()
	quit(0)


func _capture_actions(_agent_id: String, actions: Array) -> void:
	for action in actions:
		var target := String(action.params.get("target", action.params.get("object", "")))
		if not target.is_empty():
			emitted_targets.append(target)


func _fail(message: String) -> void:
	push_error("GESTURE_PIPELINE_FAIL: " + message)
	quit(1)
