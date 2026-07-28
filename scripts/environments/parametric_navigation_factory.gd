# Roadmap: S4.2
# Responsibility: Build deterministic grid NavigationMesh data from Manifest
# room bounds and Registry collision AABBs. Does not perform scene generation.
# Collaborators: ParametricSceneBuilder
# Tests: scripts/debug/parametric_living_room_structure_check.gd

class_name ParametricNavigationFactory
extends RefCounted

const GRID_STEP := 0.25
const AGENT_RADIUS := 0.36
const OBSTACLE_PADDING := 0.0
const _RUNTIME_REGION_SCRIPT := preload(
	"res://scripts/environments/parametric_navigation_region.gd"
)


## [S4.2] 创建避开落地静态家具的 NavigationRegion3D。
func create_region(manifest: Dictionary, registry: Dictionary) -> NavigationRegion3D:
	var room: Dictionary = manifest.get("room", {})
	var safe_bounds: Dictionary = room.get("bounds", {})
	var dimensions: Dictionary = room.get("dimensions_m", {})
	var default_min := Vector3(
		-float(dimensions.get("width", 8.0)) * 0.5 + AGENT_RADIUS,
		0.0,
		-float(dimensions.get("depth", 8.0)) * 0.5 + AGENT_RADIUS,
	)
	var default_max := -default_min
	var bounds_min := _vec3(safe_bounds.get("min", [default_min.x, 0.0, default_min.z]))
	var bounds_max := _vec3(safe_bounds.get("max", [default_max.x, 0.0, default_max.z]))
	var obstacles := _collect_obstacles(manifest, registry)

	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion3D"
	region.set_script(_RUNTIME_REGION_SCRIPT)
	region.navigation_mesh = _build_mesh(bounds_min, bounds_max, obstacles)
	return region


## [S4.2] 从落地的 static/rigid 资产 AABB 生成带角色半径的平面障碍。
func _collect_obstacles(manifest: Dictionary, registry: Dictionary) -> Array[Rect2]:
	var asset_map := {}
	for entry in registry.get("assets", []):
		asset_map[String(entry.get("asset_id", ""))] = entry
	var result: Array[Rect2] = []
	for placement in manifest.get("placements", []):
		var entry: Dictionary = asset_map.get(String(placement.get("asset_id", "")), {})
		var physics_role := String(entry.get("roles", {}).get("physics", "none"))
		if physics_role == "none":
			continue
		var size := _vec3(entry.get("geometry", {}).get("aabb_m", [0.3, 0.3, 0.3]))
		var position := _vec3(placement.get("position", [0.0, 0.0, 0.0]))
		# Wall-mounted decor does not block an agent's feet.
		if position.y - size.y * 0.5 > 0.35:
			continue
		var expanded := Vector2(size.x, size.z) + Vector2.ONE * OBSTACLE_PADDING * 2.0
		result.append(Rect2(
			Vector2(position.x, position.z) - expanded * 0.5,
			expanded,
		))
	return result


## [S4.2] 将安全边界栅格化为确定性三角形导航网格。
func _build_mesh(
	bounds_min: Vector3, bounds_max: Vector3, obstacles: Array[Rect2]
) -> NavigationMesh:
	var x_values := _axis_values(bounds_min.x, bounds_max.x)
	var z_values := _axis_values(bounds_min.z, bounds_max.z)
	var vertices := PackedVector3Array()
	for z in z_values:
		for x in x_values:
			vertices.append(Vector3(x, 0.0, z))

	var mesh := NavigationMesh.new()
	mesh.agent_radius = AGENT_RADIUS
	mesh.agent_height = 1.25
	mesh.vertices = vertices
	var row_size := x_values.size()
	for z_index in range(z_values.size() - 1):
		for x_index in range(x_values.size() - 1):
			var center := Vector2(
				(x_values[x_index] + x_values[x_index + 1]) * 0.5,
				(z_values[z_index] + z_values[z_index + 1]) * 0.5,
			)
			if _inside_any(center, obstacles):
				continue
			var bottom_left := z_index * row_size + x_index
			var bottom_right := bottom_left + 1
			var top_left := (z_index + 1) * row_size + x_index
			var top_right := top_left + 1
			mesh.add_polygon(PackedInt32Array([bottom_left, top_left, top_right]))
			mesh.add_polygon(PackedInt32Array([bottom_left, top_right, bottom_right]))
	return mesh


func _inside_any(point: Vector2, obstacles: Array[Rect2]) -> bool:
	for obstacle in obstacles:
		if obstacle.has_point(point):
			return true
	return false


func _axis_values(minimum: float, maximum: float) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	var value := minimum
	while value < maximum - 0.001:
		values.append(value)
		value += GRID_STEP
	values.append(maximum)
	return values


func _vec3(value: Variant) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
