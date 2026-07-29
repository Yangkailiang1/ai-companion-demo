# Roadmap: P2.1, P2.3, P2.4
# Responsibility: Expose camera-mode switching as a discoverable UI action;
# does not implement camera movement or player locomotion.
# Collaborators: OrbitRoomCamera, PlayerCameraHint
# Tests: scripts/debug/player_first_person_check.gd

extends Button

var _camera: Camera3D


## [P2.4] 绑定镜头并同步首屏按钮文案。
func _ready() -> void:
	call_deferred("_bind_camera")


## [P2.4] 延迟到主场景登记完成后查找镜头，兼容 headless 场景装载顺序。
func _bind_camera() -> void:
	_camera = get_tree().root.find_child("Camera3D", true, false) as Camera3D
	if _camera == null or not _camera.has_method("set_view_mode"):
		disabled = true
		text = "视角不可用"
		return
	pressed.connect(_toggle_view_mode)
	_camera.view_mode_changed.connect(_on_view_mode_changed)
	_on_view_mode_changed(_camera.get_view_mode())


## [P2.4] 点击后在导演与第一人称间切换；第一人称会由相机捕获鼠标。
func _toggle_view_mode() -> void:
	if _camera == null:
		return
	var next_mode := (
		"first_person" if _camera.get_view_mode() == "observer" else "observer"
	)
	_camera.set_view_mode(next_mode)


## [P2.4] 用行为文案而非内部模式名提示玩家下一步操作。
func _on_view_mode_changed(mode: String) -> void:
	text = "返回导演视角  V" if mode == "first_person" else "进入第一人称  V"
