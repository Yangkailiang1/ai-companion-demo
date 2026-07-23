class_name CharacterExpressionDriver
extends Node

@export var fade_duration: float = 0.12
@export var agent_id: String = ""

var current_expression := "neutral"
var _catalog: Dictionary = {}
var _bindings: Dictionary = {}
var _all_channels: Array[Dictionary] = []
var _active_tween: Tween
var _cue_epoch := 0

signal expression_changed(old_expression: String, new_expression: String)


func _ready() -> void:
	if agent_id.is_empty():
		agent_id = _infer_agent_id()
	_catalog = _load_catalog()
	if MessageBus.has_signal("expression_cue"):
		MessageBus.expression_cue.connect(_on_expression_cue)
	else:
		push_warning("CharacterExpressionDriver: expression_cue signal missing")
	if MessageBus.has_signal("expression_blend_cue"):
		MessageBus.expression_blend_cue.connect(_on_expression_blend_cue)
	call_deferred("_discover_morph_targets")


func _discover_morph_targets() -> void:
	_bindings.clear()
	_all_channels.clear()
	_collect_meshes(get_parent())
	if _all_channels.is_empty():
		push_warning("CharacterExpressionDriver: no blend shapes found under character")


func _collect_meshes(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh:
			var mesh_instance := child as MeshInstance3D
			var array_mesh := mesh_instance.mesh as ArrayMesh
			if array_mesh:
				for index in range(array_mesh.get_blend_shape_count()):
					var raw_name := String(array_mesh.get_blend_shape_name(index))
					var normalized := _normalize_morph_name(raw_name)
					var binding := {"mesh": mesh_instance, "index": index, "name": raw_name}
					if not _bindings.has(normalized):
						_bindings[normalized] = []
					_bindings[normalized].append(binding)
					_all_channels.append(binding)
		_collect_meshes(child)


func _on_expression_cue(expression: String, intensity: float, context: Dictionary) -> void:
	if not _context_matches_agent(context):
		return
	var normalized := expression.strip_edges().to_lower()
	if not _catalog.has(normalized):
		normalized = "neutral"
	var old_expression := current_expression
	current_expression = normalized
	_cue_epoch += 1
	_apply_morphs(normalized, clampf(intensity, 0.0, 1.0))
	if old_expression != current_expression:
		expression_changed.emit(old_expression, current_expression)
	var transient := float(_catalog[normalized].get("transient_seconds", 0.0))
	if transient > 0.0:
		_release_transient_later(_cue_epoch, transient)


func _on_expression_blend_cue(payload: Dictionary, context: Dictionary) -> void:
	if not _context_matches_agent(context):
		return
	var normalized := String(payload.get("expression", "neutral")).strip_edges().to_lower()
	var old_expression := current_expression
	current_expression = normalized
	_cue_epoch += 1
	var intensity := clampf(float(payload.get("intensity", 1.0)), 0.0, 1.0)
	var weights: Dictionary = payload.get("morph_weights", {})
	var requested_fade := float(payload.get("fade_duration", fade_duration))
	_apply_custom_morphs(weights, intensity, requested_fade)
	if old_expression != current_expression:
		expression_changed.emit(old_expression, current_expression)
	var transient := float(payload.get("transient_seconds", payload.get("hold_seconds", 0.0)))
	if transient > 0.0:
		_release_transient_later(_cue_epoch, transient)


func _apply_morphs(expression: String, intensity: float) -> void:
	_apply_custom_morphs(_catalog[expression].get("morph_weights", {}), intensity, fade_duration)


func _apply_custom_morphs(weights: Dictionary, intensity: float, duration: float) -> void:
	if _all_channels.is_empty():
		return
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()
	var target_values: Dictionary = {}
	for morph_name in weights:
		var normalized_name := _normalize_morph_name(morph_name)
		for binding in _bindings.get(normalized_name, []):
			target_values[_binding_key(binding)] = float(weights[morph_name]) * intensity

	_active_tween = create_tween().set_parallel(true)
	for binding in _all_channels:
		var mesh_instance: MeshInstance3D = binding["mesh"]
		if not is_instance_valid(mesh_instance):
			continue
		var index: int = binding["index"]
		var target := float(target_values.get(_binding_key(binding), 0.0))
		var setter := Callable(self, "_set_blend_value").bind(mesh_instance, index)
		_active_tween.tween_method(setter, mesh_instance.get_blend_shape_value(index), target, maxf(duration, 0.01))


func _set_blend_value(value: float, mesh_instance: MeshInstance3D, index: int) -> void:
	if is_instance_valid(mesh_instance):
		mesh_instance.set_blend_shape_value(index, value)


func _release_transient_later(epoch: int, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if epoch == _cue_epoch:
		_on_expression_cue("neutral", 1.0, {"source": "transient_release"})


func get_available_morph_names() -> PackedStringArray:
	return PackedStringArray(_bindings.keys())


func _binding_key(binding: Dictionary) -> String:
	return "%s:%s" % [binding["mesh"].get_instance_id(), binding["index"]]


func _normalize_morph_name(value: String) -> String:
	return value.strip_edges().to_lower().replace(".", "_").replace("-", "_")


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


func _load_catalog() -> Dictionary:
	var path := "res://data/expression_catalog.json"
	if not FileAccess.file_exists(path):
		return {"neutral": {"morph_weights": {}}}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed.get("expressions", {"neutral": {"morph_weights": {}}})
	return {"neutral": {"morph_weights": {}}}
