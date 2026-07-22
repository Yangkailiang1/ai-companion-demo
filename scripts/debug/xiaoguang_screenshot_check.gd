# Render a quick visual QA screenshot for the Xiaoguang Yishi preview scene.
# Run with: Godot --path . --script scripts/debug/xiaoguang_screenshot_check.gd

extends SceneTree

const OUTPUT_PATH := "/private/tmp/ai_companion_xiaoguang_preview.png"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	await process_frame
	var packed := load("res://scenes/environments/xiaoguang_yishi_preview.tscn") as PackedScene
	if packed == null:
		push_error("XIAOGUANG_SCREENSHOT_FAIL: failed to load preview scene")
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	for _frame in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("XIAOGUANG_SCREENSHOT_FAIL: viewport image is empty")
		quit(1)
		return
	var err := image.save_png(OUTPUT_PATH)
	if err != OK:
		push_error("XIAOGUANG_SCREENSHOT_FAIL: could not save png, error=%d" % err)
		quit(1)
		return
	print("XIAOGUANG_SCREENSHOT_PASS path=%s size=%dx%d" % [OUTPUT_PATH, image.get_width(), image.get_height()])
	quit(0)
