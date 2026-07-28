# Verifies: S4.1
# Covers: Manifest-driven room reconstruction and 1280x720 visual acceptance.

extends SceneTree

const OUTPUT_PATH := "/private/tmp/parametric_living_room_preview.png"


func _init() -> void:
	call_deferred("_run")


## [S4.1] 实例化隔离 Preview，等待资源渲染后保存验收截图。
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load(
		"res://scenes/environments/parametric_living_room_preview.tscn"
	) as PackedScene
	if packed == null:
		push_error("PARAMETRIC_LIVING_ROOM_PREVIEW_FAIL: scene missing")
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	for _frame in range(16):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		push_error("PARAMETRIC_LIVING_ROOM_PREVIEW_FAIL: save error=%d" % error)
		quit(1)
		return
	print("PARAMETRIC_LIVING_ROOM_PREVIEW_PASS path=%s size=%dx%d" % [
		OUTPUT_PATH, image.get_width(), image.get_height(),
	])
	quit(0)
