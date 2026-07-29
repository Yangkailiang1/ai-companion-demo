# Verifies: S2.2 visual acceptance
# Covers: generated living-room door openings, visible portals and 1280x720 capture.

extends SceneTree

const OUTPUT_PATH := "/private/tmp/world_travel_portal_preview.png"


## [S2.2] 延迟生成可见入口验收图。
func _init() -> void:
	call_deferred("_run")


## [S2.2] 强制进入参数化客厅，从房间正面同时拍摄左右入口。
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var loader := scene.get_node("WorldRoot") as WorldLocationLoader
	if loader.switch_location("parametric") != "parametric":
		push_error("WORLD_TRAVEL_PORTAL_PREVIEW_FAIL: room unavailable")
		quit(1)
		return
	for _frame in range(18):
		await process_frame
	scene.get_node("UILayer").visible = false
	var camera := scene.get_node("WorldRoot/Camera3D") as Camera3D
	camera.set_process(false)
	camera.set_process_input(false)
	camera.global_position = Vector3(0.0, 4.2, 8.0)
	camera.look_at(Vector3(0.0, 1.1, 0.1), Vector3.UP)
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		push_error("WORLD_TRAVEL_PORTAL_PREVIEW_FAIL: save error=%d" % error)
		quit(1)
		return
	print("WORLD_TRAVEL_PORTAL_PREVIEW_PASS path=%s size=%dx%d" % [
		OUTPUT_PATH, image.get_width(), image.get_height(),
	])
	quit(0)
