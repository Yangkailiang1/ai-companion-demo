# Verifies: D2.2, P2.1, S1.2
# Covers: semantic two-subject composition, smooth camera ownership and restore,
# plus first-person non-interference.

extends SceneTree

var failed := false


## [D2.2] Starts the asynchronous camera contract.
func _init() -> void:
	call_deferred("_run")


## [D2.2][P2.1] Verifies story signals drive and release the real main camera.
func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	for _frame in range(5):
		await process_frame
	var camera := scene.get_node("WorldRoot/Camera3D")
	var director := root.get_node("PerformanceCameraDirector")
	var bus := root.get_node("MessageBus")
	var main_label := _find_actor_label("main_agent")
	var fill := camera.get_node("CinematicFillLight") as SpotLight3D
	var original_position: Vector3 = camera.global_position

	bus.story_started.emit("camera_contract", ["main_agent", "jue_agent"])
	bus.story_beat_started.emit(0, {
		"actor": "main_agent",
		"look_at_actor": "jue_agent",
		"say": "一起看看镜头吧。",
	})
	for _frame in range(24):
		await process_frame
	var camera_diag: Dictionary = camera.get_cinematic_diagnostics()
	var director_diag: Dictionary = director.get_diagnostics()
	_assert(bool(camera_diag.get("active", false)), "cinematic camera did not activate")
	_assert(main_label != null and not main_label.visible,
		"world-space name label remained visible during cinematic")
	_assert(fill.visible, "cinematic face fill did not activate")
	_assert(
		String(director_diag.get("last_shot_kind", "")) == "dialogue_two_shot",
		"opening dialogue was not composed as a two-shot",
	)
	_assert(int(director_diag.get("occlusion_checks", 0)) >= 1,
		"shot did not run line-of-sight checks")
	_assert(bool(director_diag.get("occlusion_free", false)),
		"director could not find a clear camera candidate")
	_assert(
		camera.global_position.distance_to(original_position) > 0.15,
		"camera did not move toward the directed shot",
	)
	bus.story_beat_started.emit(1, {
		"actor": "jue_agent",
		"say": "这是说话特写。",
	})
	await process_frame
	_assert(
		String(director.get_diagnostics().get("last_shot_kind", "")) == "dialogue_close",
		"solo dialogue did not select close-up grammar",
	)
	bus.story_beat_started.emit(2, {
		"actor": "main_agent",
		"move_to": {"waypoint": "room_center"},
	})
	await process_frame
	_assert(
		String(director.get_diagnostics().get("last_shot_kind", "")) == "movement_wide",
		"movement Beat did not select wide grammar",
	)

	bus.story_finished.emit(true, "completed")
	for _frame in range(90):
		await process_frame
	camera_diag = camera.get_cinematic_diagnostics()
	_assert(not bool(camera_diag.get("active", true)), "camera did not restore orbit")
	_assert(main_label != null and main_label.visible,
		"world-space name label was not restored")
	_assert(not fill.visible, "cinematic face fill stayed active after story")
	_assert(
		camera.global_position.distance_to(original_position) < 0.08,
		"restored observer composition drifted",
	)

	_assert(camera.set_view_mode("first_person"), "first-person mode unavailable")
	var first_person_position: Vector3 = camera.global_position
	bus.story_started.emit("camera_first_person", ["main_agent"])
	bus.story_beat_started.emit(1, {"actor": "main_agent", "say": "不要抢镜头。"})
	for _frame in range(8):
		await process_frame
	_assert(
		not bool(camera.get_cinematic_diagnostics().get("active", true)),
		"director took over first-person camera",
	)
	_assert(
		camera.global_position.distance_to(first_person_position) < 0.05,
		"first-person position changed during story cue",
	)
	bus.story_finished.emit(true, "completed")

	print("PERFORMANCE_CAMERA_DIRECTOR_%s shot=%s visibility_checks=%d" % [
		"FAIL" if failed else "PASS",
		director_diag.get("last_shot_kind", ""),
		director_diag.get("occlusion_checks", 0),
	])
	scene.free()
	quit(1 if failed else 0)


## [D2.2] Resolves an actor's presentation label by stable Agent ID.
func _find_actor_label(agent_id: String) -> Label3D:
	for candidate in get_nodes_in_group("agents"):
		if String(candidate.get("agent_name")) == agent_id:
			return candidate.get_node_or_null("AgentNameLabel") as Label3D
	return null


## [T4.2] Records one stable camera contract failure.
func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	failed = true
	push_error("PERFORMANCE_CAMERA_DIRECTOR_FAIL: " + message)
