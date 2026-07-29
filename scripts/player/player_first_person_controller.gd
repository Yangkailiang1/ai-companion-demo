# Roadmap: P2.2, P2.3
# Responsibility: Own the persistent player's collision and first-person
# movement; does not choose view modes, load locations or perform interactions.
# Collaborators: OrbitRoomCamera, WorldLocationLoader
# Tests: scripts/debug/player_first_person_check.gd

class_name PlayerFirstPersonController
extends CharacterBody3D

signal entry_teleported(yaw_radians: float)

@export var movement_speed_mps := 3.4
@export var acceleration_mps2 := 14.0
@export var standing_height_m := 0.9
@export var eye_height_m := 0.68

var _control_enabled := false
var _camera: Camera3D
var _gravity_mps2 := 9.8


## [P2.2] 初始化地面吸附、重力和相机引用。
func _ready() -> void:
	floor_snap_length = 0.25
	_gravity_mps2 = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	_camera = get_parent().get_node_or_null("Camera3D") as Camera3D


## [P2.2][P2.3] 根据视角模式启停玩家移动；停用时立即清除水平速度。
func set_control_enabled(enabled: bool) -> void:
	_control_enabled = enabled
	if not enabled:
		_stop_horizontal_motion()


## [P2.3] 返回第一人称移动输入是否启用；纯读取。
func is_control_enabled() -> bool:
	return _control_enabled


## [P2.2][S2.2] 将身体放到声明的地面入口并清空旧房间速度。
func teleport_to_floor_position(floor_position: Vector3, yaw_degrees: float = 0.0) -> void:
	var standing_position := floor_position + Vector3.UP * standing_height_m
	if is_inside_tree():
		global_position = standing_position
	else:
		position = standing_position
	rotation_degrees.y = yaw_degrees
	velocity = Vector3.ZERO
	entry_teleported.emit(rotation.y)


## [P2.3] 返回第一人称相机的世界眼位；纯读取。
func get_eye_global_position() -> Vector3:
	return global_position + Vector3.UP * eye_height_m


## [P2.2][P2.3] 应用相机相对 WASD、重力和 CharacterBody 碰撞。
func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity_mps2 * delta
	else:
		velocity.y = minf(velocity.y, 0.0)
	if not _control_enabled or _is_text_input_focused():
		_stop_horizontal_motion()
		move_and_slide()
		return
	var input_vector := _read_movement_input()
	var target_velocity := _camera_relative_velocity(input_vector)
	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration_mps2 * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration_mps2 * delta)
	move_and_slide()


## [P2.2] 读取物理 WASD 键，返回归一化二维移动意图。
func _read_movement_input() -> Vector2:
	var result := Vector2.ZERO
	if Input.is_key_pressed(KEY_A):
		result.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		result.x += 1.0
	if Input.is_key_pressed(KEY_W):
		result.y += 1.0
	if Input.is_key_pressed(KEY_S):
		result.y -= 1.0
	return result.normalized()


## [P2.2] 把二维输入投影到相机水平前/右方向并转换为目标速度。
func _camera_relative_velocity(input_vector: Vector2) -> Vector3:
	if _camera == null or input_vector.is_zero_approx():
		return Vector3.ZERO
	var forward := -_camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := _camera.global_basis.x
	right.y = 0.0
	right = right.normalized()
	return (right * input_vector.x + forward * input_vector.y) * movement_speed_mps


## [P2.2] 清除水平速度但保留垂直重力状态。
func _stop_horizontal_motion() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


## [P2.3] 判断聊天文本控件是否占有键盘焦点；纯读取。
func _is_text_input_focused() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit
