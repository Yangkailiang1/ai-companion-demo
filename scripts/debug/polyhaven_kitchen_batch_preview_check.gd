# Verifies: S4.1, O2.1
# Covers: isolated import, visible nodes, Metal rendering, screenshot evidence.

extends SceneTree

const OUTPUT_PATH := "/private/tmp/polyhaven_kitchen_batch_01_preview.png"


## [S4.1][O2.1] Schedule rendering after the root viewport becomes available.
func _init() -> void:
	call_deferred("_run")


## [S4.1][O2.1] Render the three candidates and save visual evidence.
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load(
		"res://scenes/environments/polyhaven_kitchen_batch_preview.tscn"
	) as PackedScene
	if packed == null:
		push_error("POLYHAVEN_KITCHEN_PREVIEW_FAIL: preview scene missing")
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	for asset_name in ["WoodenTable01", "WoodenChair01", "CeramicVase01"]:
		if scene.get_node_or_null(asset_name) == null:
			push_error("POLYHAVEN_KITCHEN_PREVIEW_FAIL: %s missing" % asset_name)
			quit(1)
			return
	for _frame in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		push_error("POLYHAVEN_KITCHEN_PREVIEW_FAIL: save error=%d" % error)
		quit(1)
		return
	print("POLYHAVEN_KITCHEN_PREVIEW_PASS path=%s size=%dx%d" % [
		OUTPUT_PATH,
		image.get_width(),
		image.get_height(),
	])
	quit(0)
