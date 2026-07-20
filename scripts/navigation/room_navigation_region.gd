extends NavigationRegion3D

# Deterministic runtime NavigationMesh for the greybox room. Static furniture is
# represented by expanded obstacle rectangles in scene_config.json.
const GRID_STEP := 0.25


func _enter_tree() -> void:
	navigation_mesh = _build_navigation_mesh(RoomNavigation.new())


func _ready() -> void:
	# Explicit upload is required for procedurally filled resources created while
	# the NavigationRegion3D is entering the tree.
	NavigationServer3D.region_set_navigation_mesh(get_rid(), navigation_mesh)


func _build_navigation_mesh(room: RoomNavigation) -> NavigationMesh:
	var x_values := _axis_values(room.bounds_min.x, room.bounds_max.x)
	var z_values := _axis_values(room.bounds_min.z, room.bounds_max.z)
	var vertices := PackedVector3Array()
	for z in z_values:
		for x in x_values:
			vertices.append(Vector3(x, 0.0, z))

	var mesh := NavigationMesh.new()
	mesh.agent_radius = 0.36
	mesh.agent_height = 1.25
	mesh.vertices = vertices
	var row_size := x_values.size()
	for z_index in range(z_values.size() - 1):
		for x_index in range(x_values.size() - 1):
			var center := Vector3(
				(x_values[x_index] + x_values[x_index + 1]) * 0.5,
				0.0,
				(z_values[z_index] + z_values[z_index + 1]) * 0.5
			)
			if not room.is_walkable_position(center):
				continue
			var bottom_left := z_index * row_size + x_index
			var bottom_right := bottom_left + 1
			var top_left := (z_index + 1) * row_size + x_index
			var top_right := top_left + 1
			# NavigationMesh only supports triangles (not quads/ngons). Keep +Y winding.
			mesh.add_polygon(PackedInt32Array([bottom_left, top_left, top_right]))
			mesh.add_polygon(PackedInt32Array([bottom_left, top_right, bottom_right]))
	return mesh


func _axis_values(minimum: float, maximum: float) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	var value := minimum
	while value < maximum - 0.001:
		values.append(value)
		value += GRID_STEP
	values.append(maximum)
	return values
