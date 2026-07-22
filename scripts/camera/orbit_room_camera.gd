# Orbit camera around the living-room center.
#
# Controls:
# - Right or middle mouse drag: orbit around the room center
# - Mouse wheel: zoom in/out
# - Q / E or A / D: rotate left/right for keyboard-only preview

extends Camera3D


@export var target := Vector3(0.15, 0.78, 0.35)
@export var distance: float = 8.7
@export var min_distance: float = 5.8
@export var max_distance: float = 12.0
@export var yaw: float = -0.08
@export var pitch: float = -0.68
@export var mouse_sensitivity: float = 0.006
@export var key_orbit_speed: float = 1.35
@export var zoom_step: float = 0.45

var _is_orbiting := false
var _orbit_button := MOUSE_BUTTON_NONE


func _ready() -> void:
	current = true
	_update_camera()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if mouse_event.pressed and _is_pointer_over_ui(mouse_event.position):
				_is_orbiting = false
				_orbit_button = MOUSE_BUTTON_NONE
				return
			_is_orbiting = mouse_event.pressed
			_orbit_button = mouse_event.button_index if mouse_event.pressed else MOUSE_BUTTON_NONE
			get_viewport().set_input_as_handled()
		elif mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _is_pointer_over_ui(mouse_event.position):
				return
			distance = maxf(min_distance, distance - zoom_step)
			_update_camera()
			get_viewport().set_input_as_handled()
		elif mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _is_pointer_over_ui(mouse_event.position):
				return
			distance = minf(max_distance, distance + zoom_step)
			_update_camera()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _is_orbiting:
		var motion := event as InputEventMouseMotion
		yaw -= motion.relative.x * mouse_sensitivity
		pitch = clampf(pitch - motion.relative.y * mouse_sensitivity, -1.1, -0.32)
		_update_camera()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
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


func _update_camera() -> void:
	var horizontal_distance := cos(pitch) * distance
	var offset := Vector3(
		sin(yaw) * horizontal_distance,
		sin(-pitch) * distance,
		cos(yaw) * horizontal_distance
	)
	global_position = target + offset
	look_at(target, Vector3.UP)


func _is_text_input_focused() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit


func _is_pointer_over_ui(pointer_position: Vector2) -> bool:
	var root := get_tree().current_scene
	if root == null:
		return false
	var ui := root.find_child("UI", true, false) as Control
	if ui == null:
		return false
	var blockers := [
		ui.find_child("InputArea", true, false),
		ui.find_child("ChatPanel", true, false),
		ui.find_child("HUD", true, false),
		ui.find_child("StatusPanel", true, false),
		ui.find_child("CameraHint", true, false),
	]
	for node in blockers:
		if node is Control and (node as Control).visible:
			var rect := (node as Control).get_global_rect()
			if rect.has_point(pointer_position):
				return true
	return false
