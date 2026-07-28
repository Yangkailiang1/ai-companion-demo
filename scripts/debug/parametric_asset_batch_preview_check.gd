# Verifies: S4.1
# Covers: KayKit Furniture Bits batch 01 import, material dependencies and visual preview.

extends SceneTree

const OUTPUT_PATH := "/private/tmp/kaykit_furniture_batch_01_preview.png"


## [S4.1] 渲染隔离批次并保存 1280x720 Metal 验收截图。
func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load("res://scenes/environments/parametric_asset_batch_preview.tscn") as PackedScene
	if packed == null:
		push_error("PARAMETRIC_ASSET_PREVIEW_FAIL: preview scene missing")
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	for asset_name in ["ArmchairPillows", "CouchPillows", "LampStanding"]:
		if scene.get_node_or_null(asset_name) == null:
			push_error("PARAMETRIC_ASSET_PREVIEW_FAIL: %s missing" % asset_name)
			quit(1)
			return
	for _frame in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		push_error("PARAMETRIC_ASSET_PREVIEW_FAIL: save error=%d" % error)
		quit(1)
		return
	print("PARAMETRIC_ASSET_PREVIEW_PASS path=%s size=%dx%d" % [
		OUTPUT_PATH, image.get_width(), image.get_height(),
	])
	quit(0)
