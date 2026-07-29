# Roadmap: P2.1, P2.3, P2.4
# Responsibility: Present mode-specific camera controls; does not own camera
# state, player movement or input.
# Collaborators: OrbitRoomCamera
# Tests: scripts/debug/player_first_person_check.gd

extends Label

var _camera: Camera3D


## [P2.4] 延迟绑定主相机，避免 UI 与 WorldRoot 入树次序耦合。
func _ready() -> void:
	call_deferred("_bind_camera")


## [P2.4] 连接公开视角信号并立即同步提示文本。
func _bind_camera() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	_camera = scene.find_child("Camera3D", true, false) as Camera3D
	if _camera == null or not _camera.has_signal("view_mode_changed"):
		return
	_camera.connect("view_mode_changed", _on_camera_view_mode_changed)
	if _camera.has_signal("pointer_capture_changed"):
		_camera.connect("pointer_capture_changed", _on_pointer_capture_changed)
	_refresh_hint()


## [P2.4] 视角模式变化后刷新控制说明。
func _on_camera_view_mode_changed(_mode: String) -> void:
	_refresh_hint()


## [P2.3] 鼠标捕获状态变化后刷新释放/重捕获说明。
func _on_pointer_capture_changed(_is_captured: bool) -> void:
	_refresh_hint()


## [P2.1][P2.3] 根据模式与鼠标捕获状态显示简洁操作说明。
func _refresh_hint() -> void:
	if _camera == null or _camera.get_view_mode() == "observer":
		text = "观察｜右键 · 滚轮 · Q/E · V 第一人称"
	elif _camera.is_pointer_captured():
		text = "第一人称｜WASD · 移动鼠标视角 · Esc 释放"
	else:
		text = "第一人称｜右键重新锁定 · V 观察"
