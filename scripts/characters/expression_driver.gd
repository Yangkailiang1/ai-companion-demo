# Roadmap: C3.1, C6.2
# Responsibility: 把语义表情权重映射到当前角色的 blend shapes 并平滑过渡；
# 不推断情绪、不生成表情资产，也不控制身体动作。
# Collaborators: MessageBus, CharacterAdapterRegistry, ExpressionIntentRouter
# Tests: scripts/debug/expression_router_check.gd, scripts/debug/chibi_runtime_binding_check.gd

class_name CharacterExpressionDriver
extends Node

@export var fade_duration: float = 0.12
@export var agent_id: String = ""

var current_expression := "neutral"
var _catalog: Dictionary = {}
var _bindings: Dictionary = {}
var _channel_aliases: Dictionary = {}
var _all_channels: Array[Dictionary] = []
var _active_tween: Tween
var _cue_epoch := 0

signal expression_changed(old_expression: String, new_expression: String)


## [C3.1][C6.2] 发现表情通道并监听运行时角色 manifest 的迟到注册。
func _ready() -> void:
	if agent_id.is_empty():
		agent_id = _infer_agent_id()
	_catalog = _load_catalog()
	_channel_aliases = _load_channel_aliases()
	if has_node("/root/CharacterAdapterRegistry"):
		var registry := get_node("/root/CharacterAdapterRegistry")
		if not registry.runtime_adapter_registered.is_connected(_on_runtime_adapter_registered):
			registry.runtime_adapter_registered.connect(_on_runtime_adapter_registered)
	if MessageBus.has_signal("expression_cue"):
		MessageBus.expression_cue.connect(_on_expression_cue)
	else:
		push_warning("CharacterExpressionDriver: expression_cue signal missing")
	if MessageBus.has_signal("expression_blend_cue"):
		MessageBus.expression_blend_cue.connect(_on_expression_blend_cue)
	call_deferred("_discover_morph_targets")


## [C6.2][C3.1] 当前角色注册后刷新 morph 别名和绑定，消除节点加载顺序依赖。
func _on_runtime_adapter_registered(registered_agent_id: String) -> void:
	if registered_agent_id != agent_id:
		return
	_channel_aliases = _load_channel_aliases()
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
		for normalized_name in _candidate_channel_names(String(morph_name)):
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


func _candidate_channel_names(library_name: String) -> Array[String]:
	var normalized := _normalize_morph_name(library_name)
	var candidates: Array[String] = [normalized]
	var mapped = _channel_aliases.get(normalized, [])
	if mapped is String:
		mapped = [mapped]
	if mapped is Array:
		for value in mapped:
			var alias := _normalize_morph_name(String(value))
			if not alias.is_empty() and alias not in candidates:
				candidates.append(alias)
	return candidates


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


func _load_channel_aliases() -> Dictionary:
	var aliases := {}
	if has_node("/root/CharacterAdapterRegistry"):
		var raw: Dictionary = get_node("/root/CharacterAdapterRegistry").get_expression_channel_map(agent_id)
		for key in raw:
			var normalized_key := _normalize_morph_name(String(key))
			var values = raw[key]
			if values is String:
				aliases[normalized_key] = [_normalize_morph_name(values)]
			elif values is Array:
				var normalized_values: Array[String] = []
				for value in values:
					var alias := _normalize_morph_name(String(value))
					if not alias.is_empty() and alias not in normalized_values:
						normalized_values.append(alias)
				aliases[normalized_key] = normalized_values
	return aliases


func _load_catalog() -> Dictionary:
	var path := "res://data/expression_catalog.json"
	if not FileAccess.file_exists(path):
		return {"neutral": {"morph_weights": {}}}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed.get("expressions", {"neutral": {"morph_weights": {}}})
	return {"neutral": {"morph_weights": {}}}
