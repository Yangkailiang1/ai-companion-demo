# Render a quick visual QA screenshot for the main playable scene.
# Run with: Godot --path . --script scripts/debug/main_screenshot_check.gd

extends SceneTree

const OUTPUT_PATH := "/private/tmp/ai_companion_main_preview.png"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	await process_frame
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		push_error("MAIN_SCREENSHOT_FAIL: failed to load main scene")
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	for _frame in range(18):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("MAIN_SCREENSHOT_FAIL: viewport image is empty")
		quit(1)
		return
	var err := image.save_png(OUTPUT_PATH)
	if err != OK:
		push_error("MAIN_SCREENSHOT_FAIL: could not save png, error=%d" % err)
		quit(1)
		return
	print("MAIN_SCREENSHOT_PASS path=%s size=%dx%d" % [OUTPUT_PATH, image.get_width(), image.get_height()])
	quit(0)
