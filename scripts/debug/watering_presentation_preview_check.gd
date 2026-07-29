# Verifies: C4.4, C9.5b, S3.1
# Covers: watering-can tilt, visible water stream and Metal screenshot.

extends SceneTree

const OUTPUT_PATH := "/private/tmp/ai_companion_watering_preview.png"


## [C9.5b] 延迟构建参数化住宅并拍摄浇水表现。
func _init() -> void:
	call_deferred("_run")


## [S3.1] 在阳台植物旁布置水壶，截取倾倒中段的可见水流。
func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.get_node("AutonomousBehaviorSystem").set_scheduler_enabled(false)
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var loader := scene.get_node("WorldRoot") as WorldLocationLoader
	loader.switch_location("parametric")
	for _frame in range(8):
		await process_frame
	loader.travel_to("sunroom")
	for _frame in range(10):
		await process_frame
	scene.get_node("UILayer").visible = false
	loader.get_node("Sunroom/Agent").visible = false
	var room := loader.get_node("Sunroom") as Node3D
	var can_body := room.get_node(
		"SunroomWateringCan/PhysicsBody"
	) as RigidBody3D
	can_body.freeze = true
	can_body.collision_layer = 0
	can_body.collision_mask = 0
	var anchor := Node3D.new()
	anchor.name = "WateringPreviewAnchor"
	room.add_child(anchor)
	anchor.position = Vector3(-1.35, 1.1, -1.8)
	anchor.rotation_degrees.y = 180.0
	can_body.reparent(anchor, false)
	can_body.transform = Transform3D.IDENTITY
	var camera := scene.get_node("WorldRoot/Camera3D") as Camera3D
	camera.set_process(false)
	camera.set_process_input(false)
	camera.global_position = room.to_global(Vector3(0.45, 2.05, 1.0))
	camera.look_at(room.to_global(Vector3(-1.75, 0.95, -2.05)), Vector3.UP)
	var presentation := can_body.find_child(
		"StylizedWateringCan", true, false
	)
	if presentation == null:
		push_error("WATERING_PREVIEW_FAIL: presentation missing")
		quit(1)
		return
	presentation.play_tool_use("water")
	await create_timer(0.48).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("WATERING_PREVIEW_FAIL: empty image")
		quit(1)
		return
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		push_error("WATERING_PREVIEW_FAIL: save error=%d" % error)
		quit(1)
		return
	print("WATERING_PREVIEW_PASS path=%s size=%dx%d" % [
		OUTPUT_PATH, image.get_width(), image.get_height(),
	])
	quit(0)
