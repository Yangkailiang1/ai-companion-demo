# Roadmap: P2.1, P2.3, P2.4
# Responsibility: Switch and operate observer/first-person camera modes; does
# not move the player body, load locations or mutate chat UI.
# Collaborators: PlayerFirstPersonController, PlayerCameraHint
# Tests: scripts/debug/camera_orbit_check.gd,
# scripts/debug/player_first_person_check.gd

extends Camera3D

signal view_mode_changed(mode: String)

const MODE_OBSERVER := "observer"
const MODE_FIRST_PERSON := "first_person"

@export var target := Vector3(0.15, 0.78, 0.35)
@export var distance := 8.7
@export var min_distance := 5.8
@export var max_distance := 12.0
@export var yaw := -0.08
@export var pitch := -0.68
@export var mouse_sensitivity := 0.006
@export var key_orbit_speed := 1.35
@export var zoom_step := 0.45

var _view_mode := MODE_OBSERVER
var _first_person_yaw := 0.0
var _first_person_pitch := -0.12
var _is_orbiting := false
var _orbit_button := MOUSE_BUTTON_NONE
var _player: CharacterBody3D


## [P2.1][P2.3] 初始化默认观察模式并绑定持久玩家身体。
func _ready() -> void:
	current = true
	_player = get_parent().get_node_or_null("PlayerBody") as CharacterBody3D
	if _player != null:
		_player.set_control_enabled(false)
		_player.entry_teleported.connect(_on_player_entry_teleported)
	_update_camera()


## [P2.4] 切换稳定视角模式；非法模式不改变状态并返回 false。
func set_view_mode(mode: String) -> bool:
	if mode not in [MODE_OBSERVER, MODE_FIRST_PERSON]:
		return false
	if mode == _view_mode:
		return true
	if mode == MODE_FIRST_PERSON and _player == null:
		return false
	_view_mode = mode
	_is_orbiting = false
	_orbit_button = MOUSE_BUTTON_NONE
	if _player != null:
		_player.set_control_enabled(mode == MODE_FIRST_PERSON)
	if mode == MODE_FIRST_PERSON:
		_first_person_yaw = _player.global_rotation.y
		get_viewport().gui_release_focus()
	_update_camera()
	view_mode_changed.emit(_view_mode)
	return true


## [P2.4] 返回当前稳定视角模式；纯读取。
func get_view_mode() -> String:
	return _view_mode


## [P2.4] V 键切换模式；鼠标拖拽/滚轮按模式更新视角。
func _input(event: InputEvent) -> void:
	if _is_text_input_focused():
		if event is InputEventMouseButton and not event.pressed:
			_is_orbiting = false
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_V:
			set_view_mode(
				MODE_FIRST_PERSON if _view_mode == MODE_OBSERVER else MODE_OBSERVER
			)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and _is_orbiting:
		_handle_mouse_drag(event as InputEventMouseMotion)


## [P2.1][P2.3] 处理视角拖拽与观察模式滚轮缩放。
func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		if event.pressed and _is_pointer_over_ui(event.position):
			_is_orbiting = false
			return
		_is_orbiting = event.pressed
		_orbit_button = event.button_index if event.pressed else MOUSE_BUTTON_NONE
		get_viewport().set_input_as_handled()
	elif _view_mode == MODE_OBSERVER and event.pressed:
		if _is_pointer_over_ui(event.position):
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(min_distance, distance - zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(max_distance, distance + zoom_step)
		else:
			return
		_update_camera()
		get_viewport().set_input_as_handled()


## [P2.1][P2.3] 更新当前模式的 yaw/pitch 并刷新相机。
func _handle_mouse_drag(event: InputEventMouseMotion) -> void:
	if _view_mode == MODE_OBSERVER:
		yaw -= event.relative.x * mouse_sensitivity
		pitch = clampf(pitch - event.relative.y * mouse_sensitivity, -1.1, -0.32)
	else:
		_first_person_yaw -= event.relative.x * mouse_sensitivity
		_first_person_pitch = clampf(
			_first_person_pitch - event.relative.y * mouse_sensitivity, -1.2, 1.2
		)
	_update_camera()
	get_viewport().set_input_as_handled()


## [P2.1][P2.3] 驱动观察模式键盘环绕或持续同步第一人称眼位。
func _process(delta: float) -> void:
	if _view_mode == MODE_FIRST_PERSON:
		_update_camera()
		return
	if _is_text_input_focused():
		return
	var direction := 0.0
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction += 1.0
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction -= 1.0
	if not is_zero_approx(direction):
		yaw += direction * key_orbit_speed * delta
		_update_camera()


## [P2.1][P2.3] 按当前模式写入相机世界变换。
func _update_camera() -> void:
	if _view_mode == MODE_FIRST_PERSON and _player != null:
		global_position = _player.get_eye_global_position()
		global_rotation = Vector3(_first_person_pitch, _first_person_yaw, 0.0)
		return
	var horizontal_distance := cos(pitch) * distance
	var offset := Vector3(
		sin(yaw) * horizontal_distance,
		sin(-pitch) * distance,
		cos(yaw) * horizontal_distance
	)
	global_position = target + offset
	look_at(target, Vector3.UP)


## [P2.3][S2.2] 地点入口传送后同步第一人称朝向。
func _on_player_entry_teleported(yaw_radians: float) -> void:
	_first_person_yaw = yaw_radians
	if _view_mode == MODE_FIRST_PERSON:
		_update_camera()


## [P2.3] 判断聊天文本控件是否占有键盘焦点；纯读取。
func _is_text_input_focused() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit


## [P2.1][P2.3] 判断指针是否落在会阻挡镜头的 UI 区域。
func _is_pointer_over_ui(pointer_position: Vector2) -> bool:
	var root_node := get_tree().current_scene
	if root_node == null:
		return false
	var ui := root_node.find_child("UI", true, false) as Control
	if ui == null:
		return false
	for node_name in ["InputArea", "ChatPanel", "HUD", "StatusPanel", "CameraHint"]:
		var node := ui.find_child(node_name, true, false) as Control
		if node != null and node.visible and node.get_global_rect().has_point(pointer_position):
			return true
	return false
