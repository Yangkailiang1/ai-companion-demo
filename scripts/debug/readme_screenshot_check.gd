# Roadmap: O4, X2.2
# Responsibility: 生成可复现的公开 README 实机截图；不加载或复制受限本地角色资产。
# Tests: 本文件本身验证三张 1280x720 PNG 可成功写出。

extends SceneTree

const OUTPUTS := {
	"hero": "/private/tmp/ai_living_town_public_hero.png",
	"room": "/private/tmp/ai_living_town_public_room.png",
	"props": "/private/tmp/ai_living_town_public_props.png",
}


## [O4][X2.2] 延迟生成公开文档截图，确保 RenderingServer 已初始化。
func _init() -> void:
	call_deferred("_run")


## [O4][X2.2] 依次拍摄 UI 全景、房间近景和物体交互近景。
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	for _frame in range(18):
		await process_frame
	await create_timer(0.45).timeout
	# Public marketing screenshots avoid even placeholder confusion: optional local
	# characters are documented separately and never pictured without clear licensing.
	scene.get_node("WorldRoot/LivingRoom/JueAgent").visible = false
	var camera := scene.get_node("WorldRoot/Camera3D") as Camera3D
	camera.set_process(false)
	camera.set_process_input(false)
	if not await _capture(OUTPUTS.hero):
		quit(1)
		return
	scene.get_node("UILayer").visible = false
	camera.global_position = Vector3(0.2, 4.0, 5.2)
	camera.look_at(Vector3(0.2, 0.8, 0.25), Vector3.UP)
	if not await _capture(OUTPUTS.room):
		quit(1)
		return
	camera.global_position = Vector3(3.55, 2.65, 4.15)
	camera.look_at(Vector3(1.35, 0.68, -0.35), Vector3.UP)
	if not await _capture(OUTPUTS.props):
		quit(1)
		return
	print("README_SCREENSHOT_PASS outputs=%s" % str(OUTPUTS.values()))
	quit(0)


## [O4][X2.2] 保存当前视口；失败时返回 false 并输出明确路径。
func _capture(path: String) -> bool:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("README_SCREENSHOT_FAIL: empty viewport for %s" % path)
		return false
	var error := image.save_png(path)
	if error != OK:
		push_error("README_SCREENSHOT_FAIL: error=%d path=%s" % [error, path])
		return false
	return true
