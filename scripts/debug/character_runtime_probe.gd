extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/living_room.tscn")
	var room := scene.instantiate()
	root.add_child(room)
	await process_frame
	await process_frame
	for agent_path in ["Agent", "JueAgent"]:
		var agent := room.get_node_or_null(agent_path)
		if agent == null:
			print("CHARACTER_PROBE missing=%s" % agent_path)
			continue
		print("CHARACTER_PROBE agent=%s name=%s" % [agent_path, agent.get("agent_name")])
		_dump_animation_players(agent)
		_dump_skeletons(agent)
		_dump_blend_shapes(agent)
	room.queue_free()
	await process_frame
	quit(0)


func _dump_animation_players(node: Node) -> void:
	for player in _collect_nodes_of_type(node, "AnimationPlayer"):
		var animation_player := player as AnimationPlayer
		print("  AnimationPlayer path=%s animations=%s" % [
			animation_player.get_path(),
			JSON.stringify(Array(animation_player.get_animation_list())),
		])


func _dump_skeletons(node: Node) -> void:
	for skeleton_node in _collect_nodes_of_type(node, "Skeleton3D"):
		var skeleton := skeleton_node as Skeleton3D
		var names: Array[String] = []
		for index in range(skeleton.get_bone_count()):
			names.append(skeleton.get_bone_name(index))
		print("  Skeleton path=%s bones=%d names=%s" % [
			skeleton.get_path(),
			skeleton.get_bone_count(),
			JSON.stringify(names),
		])


func _dump_blend_shapes(node: Node) -> void:
	for mesh_node in _collect_nodes_of_type(node, "MeshInstance3D"):
		var mesh_instance := mesh_node as MeshInstance3D
		var array_mesh := mesh_instance.mesh as ArrayMesh
		if not array_mesh:
			continue
		var names: Array[String] = []
		for index in range(array_mesh.get_blend_shape_count()):
			names.append(String(array_mesh.get_blend_shape_name(index)))
		if not names.is_empty():
			print("  BlendShapes mesh=%s names=%s" % [mesh_instance.get_path(), JSON.stringify(names)])


func _collect_nodes_of_type(node: Node, type_name: String) -> Array[Node]:
	var result: Array[Node] = []
	if node.is_class(type_name):
		result.append(node)
	for child in node.get_children():
		result.append_array(_collect_nodes_of_type(child, type_name))
	return result
