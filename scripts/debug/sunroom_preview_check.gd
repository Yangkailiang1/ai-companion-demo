# Verifies: S1.2, S2.2, S3.1, S4.3
# Covers: seed-404 sunroom composition, active lighting and 1280x720 capture.

extends SceneTree

const OUTPUT_PATH := "/private/tmp/ai_companion_sunroom_preview.png"


## [S1.2][S4.3] 延迟构建完整住宅并拍摄阳台绿植房。
func _init() -> void:
	call_deferred("_run")


## [S2.2][S3.1] 激活新地点，从开放正面拍摄植物、家具和物理道具。
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var loader := scene.get_node("WorldRoot") as WorldLocationLoader
	if loader.switch_location("parametric") != "parametric":
		push_error("SUNROOM_PREVIEW_FAIL: parametric home unavailable")
		quit(1)
		return
	for _frame in range(8):
		await process_frame
	if not loader.travel_to("sunroom"):
		push_error("SUNROOM_PREVIEW_FAIL: sunroom unavailable")
		quit(1)
		return
	for _frame in range(12):
		await process_frame
	scene.get_node("UILayer").visible = false
	loader.get_node("Sunroom/Agent").visible = false
	var camera := scene.get_node("WorldRoot/Camera3D") as Camera3D
	camera.set_process(false)
	camera.set_process_input(false)
	camera.global_position = Vector3(22.25, 3.9, 5.7)
	camera.look_at(Vector3(22.25, 0.95, -0.7), Vector3.UP)
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("SUNROOM_PREVIEW_FAIL: viewport image is empty")
		quit(1)
		return
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		push_error("SUNROOM_PREVIEW_FAIL: save error=%d" % error)
		quit(1)
		return
	print("SUNROOM_PREVIEW_PASS path=%s size=%dx%d" % [
		OUTPUT_PATH, image.get_width(), image.get_height(),
	])
	quit(0)
