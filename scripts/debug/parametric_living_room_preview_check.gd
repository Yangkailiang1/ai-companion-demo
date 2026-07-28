# Verifies: S4.1
# Covers: Manifest-driven room reconstruction and 1280x720 visual acceptance.

extends SceneTree

const OUTPUTS := {
	"res://data/scene_generation/manifests/living_room_shadow.seed42.manifest.json":
		"/private/tmp/parametric_living_room_preview.png",
	"res://data/scene_generation/manifests/living_room_shadow.seed43.manifest.json":
		"/private/tmp/parametric_living_room_seed43_preview.png",
}


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
	for manifest_path in OUTPUTS:
		var scene := packed.instantiate()
		scene.set("manifest_path", manifest_path)
		root.add_child(scene)
		current_scene = scene
		for _frame in range(16):
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var output_path: String = OUTPUTS[manifest_path]
		var error := image.save_png(output_path)
		if error != OK:
			push_error("PARAMETRIC_LIVING_ROOM_PREVIEW_FAIL: save error=%d" % error)
			quit(1)
			return
		print("PARAMETRIC_LIVING_ROOM_PREVIEW_PASS seed=%s path=%s size=%dx%d" % [
			manifest_path, output_path, image.get_width(), image.get_height(),
		])
		scene.queue_free()
		await process_frame
	quit(0)
