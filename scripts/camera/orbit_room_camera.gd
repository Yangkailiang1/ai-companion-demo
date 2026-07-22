# Orbit camera around the living-room center.
#
# Controls:
# - Right mouse drag: orbit around the room center
# - Mouse wheel: zoom in/out
# - Q / E: rotate left/right for keyboard-only preview

extends Camera3D


@export var target := Vector3(0.35, 0.75, 0.4)
@export var distance: float = 9.4
@export var min_distance: float = 5.8
@export var max_distance: float = 12.0
@export var yaw: float = 0.0
@export var pitch: float = -0.72
@export var mouse_sensitivity: float = 0.006
@export var key_orbit_speed: float = 1.35
@export var zoom_step: float = 0.45

var _is_orbiting := false


func _ready() -> void:
	current = true
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			_is_orbiting = mouse_event.pressed
		elif mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(min_distance, distance - zoom_step)
			_update_camera()
		elif mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(max_distance, distance + zoom_step)
			_update_camera()
	elif event is InputEventMouseMotion and _is_orbiting:
		var motion := event as InputEventMouseMotion
		yaw -= motion.relative.x * mouse_sensitivity
		pitch = clampf(pitch - motion.relative.y * mouse_sensitivity, -1.1, -0.32)
		_update_camera()


func _process(delta: float) -> void:
	var direction := 0.0
	if Input.is_key_pressed(KEY_Q):
		direction += 1.0
	if Input.is_key_pressed(KEY_E):
		direction -= 1.0
	if not is_zero_approx(direction):
		yaw += direction * key_orbit_speed * delta
		_update_camera()


func _update_camera() -> void:
	var horizontal_distance := cos(pitch) * distance
	var offset := Vector3(
		sin(yaw) * horizontal_distance,
		sin(-pitch) * distance,
		cos(yaw) * horizontal_distance
	)
	global_position = target + offset
	look_at(target, Vector3.UP)
