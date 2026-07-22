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
	camera._input(press)

	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(180, -40)
	camera._input(drag)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	camera._input(release)

	await process_frame
	var moved_distance := camera.global_position.distance_to(initial_position)
	_assert(moved_distance > 0.5, "camera did not orbit enough: %.3f" % moved_distance)
	_assert(camera.global_position.distance_to(Vector3(0.15, 0.78, 0.35)) > 5.0, "camera too close to orbit target")

	print("CAMERA_ORBIT_PASS moved=%.3f pos=%s" % [moved_distance, camera.global_position])
	scene.free()
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("CAMERA_ORBIT_FAIL: " + message)
	quit(1)
