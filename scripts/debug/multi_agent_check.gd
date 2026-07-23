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
	var jue_pose_overlay = jue_agent.get_node_or_null("CharacterPoseOverlay")
	var jue_model_root: Node3D = jue_agent.get_node_or_null("JueModelRoot")
	_assert(main_driver != null and jue_driver != null, "both agents need animation drivers")
	_assert(jue_pose_overlay != null, "Jue needs skeleton pose overlay")
	_assert(jue_pose_overlay.is_overlay_enabled(), "Jue skeleton pose overlay should be enabled")
	_assert(jue_pose_overlay.get_resolved_bone_names().has("head"), "Jue pose overlay should resolve head bone")
	_assert(jue_pose_overlay.get_resolved_bone_names().has("right_hand"), "Jue pose overlay should resolve right hand bone")
	_assert(jue_model_root != null, "Jue needs procedural model root")
	var adapter_registry := root.get_node_or_null("CharacterAdapterRegistry")
	_assert(adapter_registry != null, "CharacterAdapterRegistry autoload must exist")
	_assert(adapter_registry.get_motion_adapter_type("main_agent") == "animation_player", "main agent should use animation clips")
	_assert(adapter_registry.get_motion_adapter_type("jue_agent") == "procedural_root_fallback", "Jue should use procedural fallback until retargeted clips exist")
	_assert(adapter_registry.map_clip("main_agent", "talk", "talk") == "idle", "main talk cue should map to idle clip")
	_assert(adapter_registry.map_clip("jue_agent", "offline_smoke_walk", "offline_smoke_walk") == "walk", "Jue offline clip should safely map to walk")
	var base_rotation := jue_model_root.rotation
	_assert(absf(base_rotation.y) < 0.001, "Jue model root must keep the verified front-facing orientation")
	var jue_skeleton_adapter: Dictionary = adapter_registry.get_skeleton_adapter("jue_agent")
	var jue_rest_pose: Dictionary = jue_skeleton_adapter.get("rest_pose_degrees", {})
	_assert(float(jue_rest_pose["left_upper_arm"][1]) > 45.0, "Jue left arm idle correction must use positive local Y")
	_assert(float(jue_rest_pose["right_upper_arm"][1]) < -45.0, "Jue right arm idle correction must use negative local Y")

	var bus := root.get_node_or_null("MessageBus")
	_assert(bus != null, "MessageBus autoload must exist")
	bus.emit_signal("performance_cue", "wave", {"agent_id": "jue_agent", "source": "multi_agent_check"})
	await create_timer(0.2).timeout
	_assert(jue_driver.get_current_gesture() == "wave", "targeted Jue cue should move Jue")
	_assert(jue_pose_overlay.get_current_overlay_gesture() == "wave", "targeted Jue cue should enter pose overlay wave")
	_assert(main_driver.get_current_gesture() != "wave", "targeted Jue cue must not move main agent")
	_assert(jue_model_root.rotation.distance_to(base_rotation) < 0.001, "Jue skeleton wave must not tip the whole model root")

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
