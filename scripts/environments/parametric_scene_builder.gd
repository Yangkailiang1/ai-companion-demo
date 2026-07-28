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
var _navigation_factory: ParametricNavigationFactory


## [S4.1] 初始化并设置工厂。
func _init() -> void:
	_factory = ParametricAssetFactory.new()
	_navigation_factory = ParametricNavigationFactory.new()


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
	structure.add_child(_navigation_factory.create_region(manifest, registry))

	# Place all objects.
	var placements: Array = manifest.get("placements", [])
	for placement in placements:
		var placement_node := _factory.create_placement(placements_node, placement)
		_register_semantic_placement(placement_node, placement)

	# Build report.
	return _build_report(placements_node, placements)


## [S4.2] 将生成物体及其交互 Body 绑定到 SemanticWorld。
func _register_semantic_placement(container: Node3D, placement: Dictionary) -> void:
	var interaction_node: Node3D = container
	var body := container.get_node_or_null("PhysicsBody") as Node3D
	if body != null:
		interaction_node = body
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var semantic_world := tree.root.get_node_or_null("SemanticWorld")
	if semantic_world != null and semantic_world.has_method("upsert_generated_object"):
		semantic_world.upsert_generated_object(placement, interaction_node)


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
	var openings: Array = room.get("openings", [])
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

		var material := StandardMaterial3D.new()
		material.albedo_color = WALL_MATERIAL_COLOR
		material.roughness = 0.95
		var wall_openings := openings.filter(
			func(opening: Dictionary) -> bool:
				return String(opening.get("wall_id", "")) == wall_id
		)
		if wall_openings.is_empty():
			_add_full_wall(
				wall_body, wall_id, thickness, wall_height,
				bounds_min, bounds_max, material,
			)
		else:
			_add_wall_with_openings(
				wall_body, wall_id, thickness, wall_height,
				bounds_min, bounds_max, wall_openings, material,
			)
		wall_count += 1

	# Record actual wall count for test verification.
	parent.set_meta("wall_count", wall_count)
	print("  walls built: %d" % wall_count)


## [S4.2] 创建没有门窗开口的完整墙段。
func _add_full_wall(
	body: StaticBody3D,
	wall_id: String,
	thickness: float,
	height: float,
	bounds_min: Vector3,
	bounds_max: Vector3,
	material: Material,
) -> void:
	match wall_id:
		"back":
			_add_wall_segment(body, wall_id, 0, Vector3(
				bounds_max.x - bounds_min.x + thickness, height, thickness,
			), Vector3(0.0, height * 0.5, bounds_min.z - thickness * 0.5), material)
		"front":
			_add_wall_segment(body, wall_id, 0, Vector3(
				bounds_max.x - bounds_min.x + thickness, height, thickness,
			), Vector3(0.0, height * 0.5, bounds_max.z + thickness * 0.5), material)
		"left":
			_add_wall_segment(body, wall_id, 0, Vector3(
				thickness, height, bounds_max.z - bounds_min.z,
			), Vector3(bounds_min.x - thickness * 0.5, height * 0.5, 0.0), material)
		"right":
			_add_wall_segment(body, wall_id, 0, Vector3(
				thickness, height, bounds_max.z - bounds_min.z,
			), Vector3(bounds_max.x + thickness * 0.5, height * 0.5, 0.0), material)


## [S4.2] 将墙按 schema v1 的单个声明开口切成左右/上下四段。
func _add_wall_with_openings(
	body: StaticBody3D,
	wall_id: String,
	thickness: float,
	height: float,
	bounds_min: Vector3,
	bounds_max: Vector3,
	openings: Array,
	material: Material,
) -> void:
	var opening: Dictionary = openings[0]
	var opening_position: Vector3 = _vec3(opening.get("position", [0.0, 1.0, 0.0]))
	var opening_size: Array = opening.get("size", [1.0, 1.0])
	var horizontal_center := opening_position.x if wall_id in ["back", "front"] else opening_position.z
	var horizontal_min := bounds_min.x if wall_id in ["back", "front"] else bounds_min.z
	var horizontal_max := bounds_max.x if wall_id in ["back", "front"] else bounds_max.z
	var opening_min := clampf(horizontal_center - float(opening_size[0]) * 0.5, horizontal_min, horizontal_max)
	var opening_max := clampf(horizontal_center + float(opening_size[0]) * 0.5, horizontal_min, horizontal_max)
	var vertical_min := clampf(opening_position.y - float(opening_size[1]) * 0.5, 0.0, height)
	var vertical_max := clampf(opening_position.y + float(opening_size[1]) * 0.5, 0.0, height)
	var wall_plane := (
		bounds_min.z - thickness * 0.5 if wall_id == "back"
		else bounds_max.z + thickness * 0.5 if wall_id == "front"
		else bounds_min.x - thickness * 0.5 if wall_id == "left"
		else bounds_max.x + thickness * 0.5
	)
	var segments := [
		[horizontal_min, opening_min, 0.0, height],
		[opening_max, horizontal_max, 0.0, height],
		[opening_min, opening_max, 0.0, vertical_min],
		[opening_min, opening_max, vertical_max, height],
	]
	var index := 0
	for segment in segments:
		var segment_width: float = segment[1] - segment[0]
		var segment_height: float = segment[3] - segment[2]
		if segment_width <= 0.001 or segment_height <= 0.001:
			continue
		var horizontal_mid: float = (segment[0] + segment[1]) * 0.5
		var vertical_mid: float = (segment[2] + segment[3]) * 0.5
		var size: Vector3
		var position: Vector3
		if wall_id in ["back", "front"]:
			size = Vector3(segment_width, segment_height, thickness)
			position = Vector3(horizontal_mid, vertical_mid, wall_plane)
		else:
			size = Vector3(thickness, segment_height, segment_width)
			position = Vector3(wall_plane, vertical_mid, horizontal_mid)
		_add_wall_segment(body, wall_id, index, size, position, material)
		index += 1
	body.set_meta("opening_count", openings.size())


## [S4.2] 创建单个墙段的视觉和一一对应的盒碰撞。
func _add_wall_segment(
	body: StaticBody3D,
	wall_id: String,
	index: int,
	size: Vector3,
	position: Vector3,
	material: Material,
) -> void:
	var suffix := "" if index == 0 else "_%d" % index
	var wall_mesh := MeshInstance3D.new()
	wall_mesh.name = "WallMesh_" + wall_id + suffix
	var box := BoxMesh.new()
	box.size = size
	wall_mesh.mesh = box
	wall_mesh.position = position
	wall_mesh.set_surface_override_material(0, material)
	body.add_child(wall_mesh)

	var wall_collision := CollisionShape3D.new()
	wall_collision.name = "WallCollision_" + wall_id + suffix
	var collision_box := BoxShape3D.new()
	collision_box.size = size
	wall_collision.shape = collision_box
	wall_collision.position = position
	body.add_child(wall_collision)


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


func _vec3(value: Variant) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
