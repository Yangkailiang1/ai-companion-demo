extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/living_room.tscn")
	var room := scene.instantiate()
	root.add_child(room)
	await process_frame
	await process_frame

	var main_agent = room.get_node_or_null("Agent")
	var jue_agent = room.get_node_or_null("JueAgent")
	_assert(main_agent != null, "main Agent must exist")
	_assert(jue_agent != null, "JueAgent must exist")
	_assert(main_agent.agent_name == "main_agent", "main Agent id mismatch")
	_assert(jue_agent.agent_name == "jue_agent", "JueAgent id mismatch")
	_assert(jue_agent.get_node_or_null("JueModelRoot/JueModel") != null, "Jue FBX model must be instanced")

	var main_driver = main_agent.get_node_or_null("CharacterAnimationDriver")
	var jue_driver = jue_agent.get_node_or_null("CharacterAnimationDriver")
	_assert(main_driver != null and jue_driver != null, "both agents need animation drivers")

	var bus := root.get_node_or_null("MessageBus")
	_assert(bus != null, "MessageBus autoload must exist")
	bus.emit_signal("performance_cue", "wave", {"agent_id": "jue_agent", "source": "multi_agent_check"})
	await create_timer(0.12).timeout
	_assert(jue_driver.get_current_gesture() == "wave", "targeted Jue cue should move Jue")
	_assert(main_driver.get_current_gesture() != "wave", "targeted Jue cue must not move main agent")

	var memory_system := root.get_node_or_null("MemorySystem")
	_assert(memory_system != null, "MemorySystem autoload must exist")
	memory_system.add_episode_for_agent("main_agent", "main memory marker", 1.0)
	memory_system.add_episode_for_agent("jue_agent", "jue memory marker", 1.0)
	var main_recent: Array = memory_system.retrieve_relevant_for_agent("main_agent", "main", 3)
	var jue_recent: Array = memory_system.retrieve_relevant_for_agent("jue_agent", "jue", 3)
	_assert(_contains_memory(main_recent, "main memory marker"), "main memory should be independent")
	_assert(_contains_memory(jue_recent, "jue memory marker"), "Jue memory should be independent")

	room.queue_free()
	await process_frame
	print("MULTI_AGENT_CHECK_PASS agents=2 targeted_cue=ok memories=separate")
	quit(0)


func _contains_memory(entries: Array, needle: String) -> bool:
	for entry in entries:
		if needle in String(entry.get("content", "")):
			return true
	return false


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("MULTI_AGENT_CHECK_FAIL: %s" % message)
	quit(1)
	assert(condition, message)
