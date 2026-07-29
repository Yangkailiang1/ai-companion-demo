# Roadmap: P2.1, P2.3, P2.4
# Responsibility: Present mode-specific camera controls; does not own camera
# state, player movement or input.
# Collaborators: OrbitRoomCamera
# Tests: scripts/debug/player_first_person_check.gd

extends Label


## [P2.4] 延迟绑定主相机，避免 UI 与 WorldRoot 入树次序耦合。
func _ready() -> void:
	call_deferred("_bind_camera")


## [P2.4] 连接公开视角信号并立即同步提示文本。
func _bind_camera() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var camera := scene.find_child("Camera3D", true, false)
	if camera == null or not camera.has_signal("view_mode_changed"):
		return
	camera.view_mode_changed.connect(_on_camera_view_mode_changed)
	_on_camera_view_mode_changed(camera.get_view_mode())


## [P2.1][P2.3] 根据已生效的相机模式显示简洁操作说明。
func _on_camera_view_mode_changed(mode: String) -> void:
	text = (
		"第一人称｜WASD · 右键视角 · V 观察"
		if mode == "first_person"
		else "观察｜右键 · 滚轮 · Q/E · V 第一人称"
	)
