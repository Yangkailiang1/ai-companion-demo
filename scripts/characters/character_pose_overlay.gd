class_name CharacterPoseOverlay
extends Node

@export var agent_id: String = ""
@export var enabled: bool = true

var _skeleton: Skeleton3D
var _adapter: Dictionary = {}
var _bone_aliases: Dictionary = {}
var _rest_pose: Dictionary = {}
var _idle_motion: Dictionary = {}
var _gesture_overlays: Dictionary = {}
var _expression_bone_map: Dictionary = {}
var _gesture_name := "idle"
var _gesture_started_msec := 0
var _gesture_duration := 0.0
var _expression_pose: Dictionary = {}
var _expression_until_msec := 0


func _ready() -> void:
	if agent_id.is_empty():
		agent_id = _infer_agent_id()
	_load_adapter()
	_skeleton = _find_skeleton(get_parent())
	if not _skeleton:
		push_warning("CharacterPoseOverlay: no Skeleton3D found for %s" % agent_id)
		return
	if MessageBus.has_signal("performance_cue"):
		MessageBus.performance_cue.connect(_on_performance_cue)
	if MessageBus.has_signal("expression_blend_cue"):
		MessageBus.expression_blend_cue.connect(_on_expression_blend_cue)
	if MessageBus.has_signal("expression_cue"):
		MessageBus.expression_cue.connect(_on_expression_cue)


func _process(_delta: float) -> void:
	if not enabled or not _skeleton:
		return
	_apply_runtime_pose()


func _load_adapter() -> void:
	if not has_node("/root/CharacterAdapterRegistry"):
		return
	_adapter = get_node("/root/CharacterAdapterRegistry").get_skeleton_adapter(agent_id)
	if not bool(_adapter.get("enabled", false)):
		enabled = false
		return
	_bone_aliases = _adapter.get("bone_aliases", {})
	_rest_pose = _adapter.get("rest_pose_degrees", {})
	_idle_motion = _adapter.get("idle_motion", {})
	_gesture_overlays = _adapter.get("gesture_overlays", {})
	_expression_bone_map = _adapter.get("expression_bone_map", {})


func is_overlay_enabled() -> bool:
	return enabled


func get_current_overlay_gesture() -> String:
	return _gesture_name


func get_resolved_bone_names() -> Dictionary:
	var result := {}
	if not _skeleton:
		return result
	for semantic_bone in _bone_aliases:
		var resolved := _resolve_bone_name(String(semantic_bone))
		if not resolved.is_empty():
			result[semantic_bone] = resolved
	return result


func get_active_expression_pose_keys() -> PackedStringArray:
	return PackedStringArray(_expression_pose.keys())


func _apply_runtime_pose() -> void:
	var now_msec := Time.get_ticks_msec()
	var pose := _copy_pose(_rest_pose)
	_merge_pose(pose, _build_idle_pose(now_msec))
	if _gesture_name != "idle" and _gesture_duration > 0.0:
		var elapsed := float(now_msec - _gesture_started_msec) / 1000.0
		var t := clampf(elapsed / _gesture_duration, 0.0, 1.0)
		if t >= 1.0:
			_gesture_name = "idle"
			_gesture_duration = 0.0
		else:
			_merge_pose(pose, _build_gesture_pose(_gesture_name, t))
	if now_msec < _expression_until_msec:
		_merge_pose(pose, _expression_pose)
	else:
		_expression_pose.clear()
	_apply_pose_to_skeleton(pose)


func _build_idle_pose(now_msec: int) -> Dictionary:
	if _idle_motion.is_empty():
		return {}
	var result := {}
	var phase := float(now_msec) / 1000.0 * TAU * float(_idle_motion.get("breath_hz", 0.28))
	var amount := sin(phase)
	var sway := sin(phase * 0.55 + 0.7)
	for key in _idle_motion.get("breath_degrees", {}):
		result[key] = _vec3_from_array(_idle_motion["breath_degrees"][key]) * amount
	for key in _idle_motion.get("sway_degrees", {}):
		result[key] = _vec3_from_array(_idle_motion["sway_degrees"][key]) * sway
	return result


func _build_gesture_pose(name: String, t: float) -> Dictionary:
	var overlay: Dictionary = _gesture_overlays.get(name, {})
	if overlay.is_empty():
		return {}
	var result := {}
	var envelope := sin(t * PI)
	var wave := sin(t * TAU * float(overlay.get("cycles", 1.0)))
	for key in overlay.get("degrees", {}):
		result[key] = _vec3_from_array(overlay["degrees"][key]) * envelope
	for key in overlay.get("oscillate_degrees", {}):
		result[key] = _vec3_from_array(overlay["oscillate_degrees"][key]) * envelope * wave
	return result


func _apply_pose_to_skeleton(pose: Dictionary) -> void:
	for semantic_bone in pose:
		var bone_name := _resolve_bone_name(String(semantic_bone))
		if bone_name.is_empty():
			continue
		var index := _skeleton.find_bone(bone_name)
		if index < 0:
			continue
		var euler := _vec3_from_variant(pose[semantic_bone])
		_skeleton.set_bone_pose_rotation(index, Quaternion.from_euler(Vector3(
			deg_to_rad(euler.x),
			deg_to_rad(euler.y),
			deg_to_rad(euler.z)
		)))


func _on_performance_cue(gesture: String, context: Dictionary) -> void:
	if not _context_matches_agent(context):
		return
	var normalized := gesture.strip_edges().to_lower()
	if has_node("/root/CharacterAdapterRegistry"):
		normalized = String(get_node("/root/CharacterAdapterRegistry").map_clip(agent_id, normalized, normalized))
	if not _gesture_overlays.has(normalized):
		return
	_gesture_name = normalized
	_gesture_started_msec = Time.get_ticks_msec()
	_gesture_duration = float(_gesture_overlays[normalized].get("duration", 1.0))


func _on_expression_blend_cue(payload: Dictionary, context: Dictionary) -> void:
	if not _context_matches_agent(context):
		return
	_apply_expression_bone_fallback(payload)


func _on_expression_cue(expression: String, intensity: float, context: Dictionary) -> void:
	if not _context_matches_agent(context):
		return
	var catalog := _load_expression_catalog()
	var payload: Dictionary = catalog.get(expression.strip_edges().to_lower(), {})
	payload["intensity"] = intensity
	_apply_expression_bone_fallback(payload)


func _apply_expression_bone_fallback(payload: Dictionary) -> void:
	var fallback: Dictionary = payload.get("bone_fallback", {})
	if fallback.is_empty():
		return
	var intensity := clampf(float(payload.get("intensity", 1.0)), 0.0, 1.0)
	var pose := {}
	for source_key in fallback:
		var target_bone := String(_expression_bone_map.get(source_key, source_key))
		pose[target_bone] = _expression_value_to_rotation(String(source_key), float(fallback[source_key]) * intensity)
	_expression_pose = pose
	var hold := float(payload.get("hold_seconds", payload.get("transient_seconds", 0.9)))
	_expression_until_msec = Time.get_ticks_msec() + int(maxf(hold, 0.35) * 1000.0)


func _expression_value_to_rotation(key: String, value: float) -> Vector3:
	match key:
		"head_pitch_degrees":
			return Vector3(value, 0, 0)
		"head_roll_degrees":
			return Vector3(0, 0, value)
		"head_yaw_degrees":
			return Vector3(0, value, 0)
		"eye_pitch_degrees":
			return Vector3(value, 0, 0)
	return Vector3.ZERO


func _merge_pose(target: Dictionary, addition: Dictionary) -> void:
	for key in addition:
		target[key] = _vec3_from_variant(target.get(key, Vector3.ZERO)) + _vec3_from_variant(addition[key])


func _copy_pose(source: Dictionary) -> Dictionary:
	var result := {}
	for key in source:
		result[key] = _vec3_from_variant(source[key])
	return result


func _resolve_bone_name(semantic_bone: String) -> String:
	var aliases = _bone_aliases.get(semantic_bone, [semantic_bone])
	if aliases is String:
		aliases = [aliases]
	for alias in aliases:
		var bone_name := String(alias)
		if _skeleton.find_bone(bone_name) >= 0:
			return bone_name
	return ""


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null


func _infer_agent_id() -> String:
	var node := get_parent()
	while node:
		if "agent_name" in node:
			return String(node.agent_name)
		node = node.get_parent()
	return "main_agent"


func _context_matches_agent(context: Dictionary) -> bool:
	var target := String(context.get("agent_id", ""))
	return target.is_empty() or target == agent_id


func _vec3_from_variant(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array:
		return _vec3_from_array(value)
	return Vector3.ZERO


func _vec3_from_array(value: Variant) -> Vector3:
	if not value is Array or value.size() < 3:
		return Vector3.ZERO
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _load_expression_catalog() -> Dictionary:
	var path := "res://data/expression_catalog.json"
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed.get("expressions", {})
	return {}
