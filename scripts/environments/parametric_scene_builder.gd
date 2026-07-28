# Roadmap: S4.1
# Responsibility: Reconstruct a room from Manifest + Registry dicts; creates
# floor, walls and delegates every placement to ParametricAssetFactory. Does
# not load JSON files, does not branch on concrete asset_id, does not set
# camera or register with SemanticWorld.
# Collaborators: ParametricAssetFactory
# Tests: scripts/debug/parametric_living_room_builder_check.gd

class_name ParametricSceneBuilder
extends RefCounted

const FLOOR_MATERIAL_COLOR := Color(0.35, 0.28, 0.22, 1.0)   # dark wood
const WALL_MATERIAL_COLOR := Color(0.92, 0.88, 0.82, 1.0)    # warm plaster

var _factory: ParametricAssetFactory


## [S4.1] 初始化并设置工厂。
func _init() -> void:
	_factory = ParametricAssetFactory.new()


## [S4.1] 从已解析的 manifest/registry 字典构建完整房间。
## 副作用：在 room_parent 下创建 GeneratedRoom/Structure 和 GeneratedRoom/Placements 子树。
## 返回包含 loaded/fallback/collision 计数的构建报告。
func build_room(room_parent: Node3D, manifest: Dictionary, registry: Dictionary) -> Dictionary:
	_factory.index_registry(registry)

	var generated_root := Node3D.new()
	generated_root.name = "GeneratedRoom"
	room_parent.add_child(generated_root)

	var structure := Node3D.new()
	structure.name = "Structure"
	generated_root.add_child(structure)

	var placements_node := Node3D.new()
	placements_node.name = "Placements"
	generated_root.add_child(placements_node)

	# Build floor and walls from manifest room data.
	var room: Dictionary = manifest.get("room", {})
	var dimensions: Dictionary = room.get("dimensions_m", {"width": 8.0, "depth": 8.0, "height": 3.0})
	var width: float = dimensions.get("width", 8.0)
	var depth: float = dimensions.get("depth", 8.0)
	var height: float = dimensions.get("height", 3.0)
	var bounds_min := Vector3(-width * 0.5, 0.0, -depth * 0.5)
	var bounds_max := Vector3(width * 0.5, height, depth * 0.5)

	_create_floor(structure, Vector2(width, depth))
	_create_walls_from_manifest(structure, room, bounds_min, bounds_max)

	# Place all objects.
	var placements: Array = manifest.get("placements", [])
	for placement in placements:
		_factory.create_placement(placements_node, placement)

	# Build report.
	return _build_report(placements_node, placements)


## [S4.1] 创建厚度 0.1m 的木色地板 StaticBody（含碰撞）。
func _create_floor(parent: Node3D, size: Vector2) -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	parent.add_child(floor_body)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "FloorMesh"
	var box := BoxMesh.new()
	box.size = Vector3(size.x, 0.1, size.y)
	mesh_instance.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = FLOOR_MATERIAL_COLOR
	material.roughness = 0.9
	mesh_instance.set_surface_override_material(0, material)
	mesh_instance.position = Vector3(0.0, -0.05, 0.0)
	floor_body.add_child(mesh_instance)

	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "FloorCollision"
	var collision_box := BoxShape3D.new()
	collision_box.size = Vector3(size.x, 0.1, size.y)
	collision_shape.shape = collision_box
	collision_shape.position = Vector3(0.0, -0.05, 0.0)
	floor_body.add_child(collision_shape)


## [S4.1] 根据 manifest 中声明的墙体创建 warm-plaster 色墙面。
## 每面墙使用各自声明的 height_m，支持 back/left/right/front 四面。
## 副作用：创建 StaticBody3D 带合围盒碰撞，并将 wall_count 写入 structure 元数据。
func _create_walls_from_manifest(parent: Node3D, room: Dictionary, bounds_min: Vector3, bounds_max: Vector3) -> void:
	var walls: Array = room.get("walls", [])
	if walls.is_empty():
		return
	var wall_count := 0
	for wall_data in walls:
		var wall_id: String = wall_data.get("wall_id", "")
		var thickness: float = wall_data.get("thickness_m", 0.2)
		var wall_height: float = wall_data.get("height_m", 3.0)

		var wall_body := StaticBody3D.new()
		wall_body.name = "Wall_" + wall_id.capitalize()
		parent.add_child(wall_body)

		var wall_mesh := MeshInstance3D.new()
		wall_mesh.name = "WallMesh_" + wall_id
		var box := BoxMesh.new()

		match wall_id:
			"back":
				box.size = Vector3(bounds_max.x - bounds_min.x + thickness, wall_height, thickness)
				wall_mesh.position = Vector3(0.0, wall_height * 0.5, bounds_min.z - thickness * 0.5)
			"front":
				box.size = Vector3(bounds_max.x - bounds_min.x + thickness, wall_height, thickness)
				wall_mesh.position = Vector3(0.0, wall_height * 0.5, bounds_max.z + thickness * 0.5)
			"left":
				box.size = Vector3(thickness, wall_height, bounds_max.z - bounds_min.z)
				wall_mesh.position = Vector3(bounds_min.x - thickness * 0.5, wall_height * 0.5, 0.0)
			"right":
				box.size = Vector3(thickness, wall_height, bounds_max.z - bounds_min.z)
				wall_mesh.position = Vector3(bounds_max.x + thickness * 0.5, wall_height * 0.5, 0.0)
			_:
				continue

		var material := StandardMaterial3D.new()
		material.albedo_color = WALL_MATERIAL_COLOR
		material.roughness = 0.95
		wall_mesh.mesh = box
		wall_mesh.set_surface_override_material(0, material)
		wall_body.add_child(wall_mesh)

		var wall_collision := CollisionShape3D.new()
		wall_collision.name = "WallCollision_" + wall_id
		var collision_box := BoxShape3D.new()
		collision_box.size = box.size
		wall_collision.shape = collision_box
		wall_collision.position = wall_mesh.position
		wall_body.add_child(wall_collision)
		wall_count += 1

	# Record actual wall count for test verification.
	parent.set_meta("wall_count", wall_count)
	print("  walls built: %d" % wall_count)


## [S4.1] 遍历 GeneratedRoom/Placements 生成包含 loaded/fallback/collision/rigid/static/none 计数的报告。
func _build_report(placements_node: Node3D, placements: Array) -> Dictionary:
	var loaded_count := 0
	var fallback_count := 0
	var collision_count := 0
	var rigid_count := 0
	var static_count := 0
	var none_count := 0

	for child in placements_node.get_children():
		if not child is Node3D:
			continue
		var phys_role: String = child.get_meta("physics_role", "none")
		match phys_role:
			"static":
				static_count += 1
				collision_count += 1
			"rigid":
				rigid_count += 1
				collision_count += 1
			_:
				none_count += 1

		if _has_loaded_model(child):
			loaded_count += 1
		else:
			fallback_count += 1

	return {
		"placements": placements.size(),
		"loaded": loaded_count,
		"fallbacks": fallback_count,
		"collisions": collision_count,
		"rigid": rigid_count,
		"static": static_count,
		"none": none_count,
	}


## [S4.1] 检查节点子树中是否存在非 BoxMesh 的 MeshInstance3D，表示加载的外部模型。
func _has_loaded_model(node: Node3D) -> bool:
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh != null:
			if not child.mesh is BoxMesh:
				return true
		if child is Node3D:
			if _has_loaded_model(child):
				return true
	return false
