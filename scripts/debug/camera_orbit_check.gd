# Acceptance check for the room orbit camera.
# Run with:
# Godot --headless --log-file /private/tmp/ai_companion_camera_orbit.log --path . --script scripts/debug/camera_orbit_check.gd

extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var packed := load("res://scenes/main.tscn") as PackedScene
	_assert(packed != null, "failed to load main scene")
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	for _frame in range(5):
		await process_frame

	var camera := scene.find_child("Camera3D", true, false) as Camera3D
	_assert(camera != null, "camera missing")
	var initial_position := camera.global_position

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.position = Vector2(640, 360)
	camera._input(press)

	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(180, -40)
	drag.position = Vector2(820, 320)
	camera._input(drag)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	release.position = Vector2(820, 320)
	camera._input(release)

	await process_frame
	var moved_distance := camera.global_position.distance_to(initial_position)
	_assert(moved_distance > 0.5, "camera did not orbit enough: %.3f" % moved_distance)
	_assert(camera.global_position.distance_to(Vector3(0.15, 0.78, 0.35)) > 5.0, "camera too close to orbit target")

	var after_orbit_position := camera.global_position

	var blocked_press := InputEventMouseButton.new()
	blocked_press.button_index = MOUSE_BUTTON_RIGHT
	blocked_press.pressed = true
	blocked_press.position = Vector2(100, 685)
	camera._input(blocked_press)

	var blocked_drag := InputEventMouseMotion.new()
	blocked_drag.relative = Vector2(240, 0)
	blocked_drag.position = Vector2(340, 685)
	camera._input(blocked_drag)
	await process_frame
	var blocked_movement := camera.global_position.distance_to(after_orbit_position)
	_assert(blocked_movement < 0.05, "camera orbited while pointer was over input UI: %.3f" % blocked_movement)

	var line_edit := scene.find_child("LineEdit", true, false) as LineEdit
	_assert(line_edit != null, "line edit missing")
	line_edit.grab_focus()
	var before_focused_keyboard := camera.global_position
	var input := InputEventKey.new()
	input.keycode = KEY_A
	input.physical_keycode = KEY_A
	input.pressed = true
	Input.parse_input_event(input)
	for _frame in range(3):
		await process_frame
	var after_focused_keyboard := camera.global_position
	_assert(after_focused_keyboard.distance_to(before_focused_keyboard) < 0.05, "camera rotated while text input was focused")

	print("CAMERA_ORBIT_PASS moved=%.3f ui_blocked=%.3f pos=%s" % [moved_distance, blocked_movement, camera.global_position])
	scene.free()
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("CAMERA_ORBIT_FAIL: " + message)
	quit(1)
