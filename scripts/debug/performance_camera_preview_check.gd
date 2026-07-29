# Verifies: D2.2, C8.3 visual acceptance
# Covers: automatic two-character framing with anime rim light at 1280x720.

extends SceneTree

const OUTPUT_PATH := "/private/tmp/performance_camera_preview.png"


## [D2.2] Starts the deferred Metal preview capture.
func _init() -> void:
	call_deferred("_run")


## [D2.2][C8.3] Frames a mutual-gaze Beat and captures the rendered result.
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	for _frame in range(12):
		await process_frame
	scene.get_node("UILayer").visible = false
	var main := _find_actor("main_agent")
	var jue := _find_actor("jue_agent")
	if main == null or jue == null:
		push_error("PERFORMANCE_CAMERA_PREVIEW_FAIL: cast unavailable")
		quit(1)
		return
	for actor in get_nodes_in_group("agents"):
		if actor != main and actor != jue:
			actor.visible = false
	main.global_position = Vector3(-0.95, 0.0, 0.15)
	jue.global_position = Vector3(0.95, 0.0, 0.15)
	main.turn_towards_world_position(jue.global_position, 0.01)
	jue.turn_towards_world_position(main.global_position, 0.01)
	var bus := root.get_node("MessageBus")
	bus.performance_cue.emit("wave", {
		"agent_id": "main_agent", "source": "preview",
	})
	bus.expression_cue.emit("happy", 0.78, {
		"agent_id": "main_agent", "source": "preview",
	})
	bus.expression_cue.emit("happy", 0.68, {
		"agent_id": "jue_agent", "source": "preview",
	})
	bus.story_started.emit("visual_preview", ["main_agent", "jue_agent"])
	bus.story_beat_started.emit(0, {
		"actor": "main_agent",
		"look_at_actor": "jue_agent",
		"say": "一起去看看夜景吧。",
	})
	await create_timer(0.85).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		push_error("PERFORMANCE_CAMERA_PREVIEW_FAIL: save error=%d" % error)
		quit(1)
		return
	print("PERFORMANCE_CAMERA_PREVIEW_PASS path=%s" % OUTPUT_PATH)
	quit(0)


## [D2.2] Finds one preview actor by stable Agent ID.
func _find_actor(agent_id: String) -> Node3D:
	for candidate in get_nodes_in_group("agents"):
		if String(candidate.get("agent_name")) == agent_id:
			return candidate as Node3D
	return null
