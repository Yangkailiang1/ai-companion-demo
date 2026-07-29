# Roadmap: S1.2, S4.1
# Responsibility: Build and activate one room's data-driven key/fill/accent
# lighting rig; does not choose the active room or alter environment geometry.
# Collaborators: ParametricRoomRuntime
# Tests: scripts/debug/parametric_room_lighting_check.gd

class_name ParametricRoomLighting
extends Node3D

const DEFAULT_KEY_COLOR := Color(1.0, 0.84, 0.7)
const DEFAULT_FILL_COLOR := Color(1.0, 0.7, 0.46)
const DEFAULT_ACCENT_COLOR := Color(0.58, 0.72, 1.0)

var _key_light: DirectionalLight3D
var _fill_light: OmniLight3D
var _accent_light: OmniLight3D
var _is_active := true


## [S1.2][S4.1] Rebuilds the three-light rig from a validated room lighting block.
## Side effects: replaces this component's light children.
func configure(lighting: Dictionary) -> void:
	for child in get_children():
		child.free()
	_key_light = _create_key_light(lighting)
	_fill_light = _create_omni_light(
		"WarmFillLight", lighting, "fill", DEFAULT_FILL_COLOR,
		Vector3(0.8, 2.35, 1.3), 0.5, 6.2,
	)
	_accent_light = _create_omni_light(
		"AccentLight", lighting, "accent", DEFAULT_ACCENT_COLOR,
		Vector3(-2.4, 1.8, -2.4), 0.24, 3.8,
	)
	add_child(_key_light)
	add_child(_fill_light)
	add_child(_accent_light)
	set_active(_is_active)


## [S1.2][S2.5] Enables the room rig only for the semantic room occupied by the
## player; global environment ambient remains available in adjacent rooms.
func set_active(active: bool) -> void:
	_is_active = active
	for light in [_key_light, _fill_light, _accent_light]:
		if is_instance_valid(light):
			light.visible = active


## [S1.2] Returns the number of currently visible lights for diagnostics.
func get_active_light_count() -> int:
	var count := 0
	for light in [_key_light, _fill_light, _accent_light]:
		if is_instance_valid(light) and light.visible:
			count += 1
	return count


## [S1.2] Creates a warm directional key with the room's authored rotation.
func _create_key_light(lighting: Dictionary) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = "KeyLight"
	light.rotation_degrees = _vector3(
		lighting.get("key_rotation_deg", [-56.0, -30.0, 0.0]),
		Vector3(-56.0, -30.0, 0.0),
	)
	light.light_color = _color(lighting.get("key_color", []), DEFAULT_KEY_COLOR)
	light.light_energy = clampf(float(lighting.get("key_energy", 0.9)), 0.0, 3.0)
	light.shadow_enabled = true
	light.light_angular_distance = 1.25
	light.shadow_opacity = 0.78
	light.directional_shadow_max_distance = 18.0
	return light


## [S1.2] Creates one bounded local light from a prefixed manifest field group.
func _create_omni_light(
	node_name: String,
	lighting: Dictionary,
	prefix: String,
	fallback_color: Color,
	fallback_position: Vector3,
	fallback_energy: float,
	fallback_range_m: float,
) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = node_name
	light.position = _vector3(
		lighting.get(prefix + "_position", []), fallback_position
	)
	light.light_color = _color(
		lighting.get(prefix + "_color", []), fallback_color
	)
	light.light_energy = clampf(
		float(lighting.get(prefix + "_energy", fallback_energy)), 0.0, 4.0
	)
	light.omni_range = clampf(
		float(lighting.get(prefix + "_range_m", fallback_range_m)), 0.5, 12.0
	)
	light.shadow_enabled = false
	return light


## [S1.2] Converts RGB arrays to a clamped opaque Color.
func _color(value: Variant, fallback: Color) -> Color:
	if value is Array and value.size() >= 3:
		return Color(
			clampf(float(value[0]), 0.0, 1.0),
			clampf(float(value[1]), 0.0, 1.0),
			clampf(float(value[2]), 0.0, 1.0),
			1.0,
		)
	return fallback


## [S1.2] Converts authored XYZ arrays without accepting malformed values.
func _vector3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback
