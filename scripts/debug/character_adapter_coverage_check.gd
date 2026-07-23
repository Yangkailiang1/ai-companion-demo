extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/living_room.tscn")
	var room := scene.instantiate()
	root.add_child(room)
	await process_frame
	await process_frame

	var registry := root.get_node_or_null("CharacterAdapterRegistry")
	_assert(registry != null, "CharacterAdapterRegistry autoload must exist")
	_validate_character(room, registry, "Agent", "main_agent")
	_validate_character(room, registry, "JueAgent", "jue_agent")
	_validate_jue_humanml3d_map(room)

	room.queue_free()
	await process_frame
	print("CHARACTER_ADAPTER_COVERAGE_PASS characters=2")
	quit(0)


func _validate_character(room: Node, registry: Node, path: String, agent_id: String) -> void:
	var agent := room.get_node_or_null(path)
	_assert(agent != null, "%s node must exist" % path)
	var character_adapter: Dictionary = registry.get_character_adapter(agent_id)
	_assert(not character_adapter.is_empty(), "%s adapter must exist" % agent_id)

	var motion_adapter: Dictionary = registry.get_motion_adapter(agent_id)
	var clip_map: Dictionary = motion_adapter.get("clip_map", {})
	for gesture in ["idle", "walk", "wave", "nod", "think", "happy", "sit", "talk"]:
		_assert(clip_map.has(gesture), "%s clip_map missing %s" % [agent_id, gesture])
	if String(motion_adapter.get("type", "")) == "animation_player":
		var player := agent.find_child("AnimationPlayer", true, false) as AnimationPlayer
		_assert(player != null, "%s animation adapter requires AnimationPlayer" % agent_id)
		for action_id in clip_map:
			var clip_name := String(clip_map[action_id])
			_assert(player.has_animation(clip_name), "%s mapped clip missing: %s -> %s" % [agent_id, action_id, clip_name])

	var skeleton_adapter: Dictionary = registry.get_skeleton_adapter(agent_id)
	if bool(skeleton_adapter.get("enabled", false)):
		var skeleton := _find_skeleton(agent)
		_assert(skeleton != null, "%s skeleton adapter requires Skeleton3D" % agent_id)
		var aliases: Dictionary = skeleton_adapter.get("bone_aliases", {})
		for semantic_bone in aliases:
			_assert(_resolve_alias(skeleton, aliases[semantic_bone]) != "", "%s unresolved semantic bone: %s" % [agent_id, semantic_bone])
	else:
		if String(motion_adapter.get("type", "")) == "animation_player":
			_assert(not String(skeleton_adapter.get("reason", "")).is_empty(), "%s disabled skeleton adapter should explain why" % agent_id)

	var expression_adapter: Dictionary = registry.get_expression_adapter(agent_id)
	var channel_map: Dictionary = expression_adapter.get("channel_map", {})
	_assert(not channel_map.is_empty(), "%s expression channel_map must not be empty" % agent_id)
	var morphs := _collect_morph_names(agent)
	var has_any_mapped_channel := false
	for semantic_channel in channel_map:
		for alias in _arrayify(channel_map[semantic_channel]):
			if _normalize(String(alias)) in morphs:
				has_any_mapped_channel = true
	_assert(has_any_mapped_channel, "%s must map at least one expression channel to a real morph" % agent_id)


func _validate_jue_humanml3d_map(room: Node) -> void:
	var agent := room.get_node_or_null("JueAgent")
	var skeleton := _find_skeleton(agent)
	_assert(skeleton != null, "Jue skeleton must exist")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/humanml3d_jue_bone_map.json"))
	_assert(parsed is Dictionary, "Jue HumanML3D map must be valid JSON")
	var joints: Array = parsed.get("joints", [])
	_assert(joints.size() == 22, "Jue HumanML3D map must have 22 joints")
	for index in range(joints.size()):
		var joint: Dictionary = joints[index]
		_assert(joint.get("index", -1) == index, "Jue HumanML3D indices must be contiguous")
		var target := String(joint.get("target", ""))
		_assert(skeleton.find_bone(target) >= 0, "Jue HumanML3D target missing from skeleton: %s" % target)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null


func _resolve_alias(skeleton: Skeleton3D, aliases: Variant) -> String:
	for alias in _arrayify(aliases):
		var bone_name := String(alias)
		if skeleton.find_bone(bone_name) >= 0:
			return bone_name
	return ""


func _collect_morph_names(node: Node) -> PackedStringArray:
	var names: Array[String] = []
	_collect_morph_names_recursive(node, names)
	return PackedStringArray(names)


func _collect_morph_names_recursive(node: Node, names: Array[String]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var array_mesh := mesh_instance.mesh as ArrayMesh
		if array_mesh:
			for index in range(array_mesh.get_blend_shape_count()):
				var normalized := _normalize(String(array_mesh.get_blend_shape_name(index)))
				if normalized not in names:
					names.append(normalized)
	for child in node.get_children():
		_collect_morph_names_recursive(child, names)


func _arrayify(value: Variant) -> Array:
	if value is Array:
		return value
	return [value]


func _normalize(value: String) -> String:
	return value.strip_edges().to_lower().replace(".", "_").replace("-", "_")


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("CHARACTER_ADAPTER_COVERAGE_FAIL: %s" % message)
	quit(1)
	assert(condition, message)
