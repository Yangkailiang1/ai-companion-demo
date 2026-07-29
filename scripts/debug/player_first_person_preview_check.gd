# Verifies: P2.3 visual acceptance
# Covers: first-person eye height, room composition and mode-specific UI hint.

extends SceneTree

const OUTPUT_PATH := "/private/tmp/player_first_person_preview.png"


## [P2.3] 延迟生成第一人称 Metal 验收图。
func _init() -> void:
	call_deferred("_run")


## [P2.3] 进入参数化客厅第一人称并保存 1280×720 截图。
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var loader := scene.get_node("WorldRoot") as WorldLocationLoader
	if loader.switch_location("parametric") != "parametric":
		push_error("PLAYER_FIRST_PERSON_PREVIEW_FAIL: room unavailable")
		quit(1)
		return
	var camera := scene.get_node("WorldRoot/Camera3D")
	if not camera.set_view_mode("first_person"):
		push_error("PLAYER_FIRST_PERSON_PREVIEW_FAIL: mode unavailable")
		quit(1)
		return
	for _frame in range(18):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		push_error("PLAYER_FIRST_PERSON_PREVIEW_FAIL: save error=%d" % error)
		quit(1)
		return
	print("PLAYER_FIRST_PERSON_PREVIEW_PASS path=%s size=%dx%d" % [
		OUTPUT_PATH, image.get_width(), image.get_height(),
	])
	quit(0)
