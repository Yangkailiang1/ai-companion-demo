# Roadmap: S4.1
# Responsibility: Instantiate or parametrically author a single placement from
# a Registry entry; owns model loading, AABB scaling, physics body/collision,
# metadata and AnchorApproach creation. Never loads manifest files, never
# branches on concrete asset_id.
# Collaborators: parametric_scene_builder.gd
# Tests: scripts/debug/parametric_living_room_builder_check.gd

class_name ParametricAssetFactory
extends RefCounted

const _ROLE_COLORS := {
	"furniture": Color(0.65, 0.42, 0.28, 1.0),  # warm wood
	"clutter": Color(0.45, 0.58, 0.65, 1.0),   # soft accent
	"organic": Color(0.35, 0.62, 0.35, 1.0),   # green
	"decor": Color(0.72, 0.63, 0.55, 1.0),     # warm beige
	"structure": Color(0.82, 0.85, 0.92, 1.0), # pale blue-white
}
const _FALLBACK_COLOR := Color(0.55, 0.55, 0.55, 1.0)
const _INTERACTABLE_SCRIPT := preload("res://scripts/objects/interactable_object.gd")
const _GENERATED_STATE_SCRIPT := preload("res://scripts/objects/generated_object_state.gd")

var _registry_index: Dictionary = {}


## [S4.1] 按 asset_id 索引整个 Registry，用于后续快速查找。
func index_registry(registry: Dictionary) -> void:
	_registry_index.clear()
	var assets: Array = registry.get("assets", [])
	for entry in assets:
		var asset_id: String = entry.get("asset_id", "")
		if not asset_id.is_empty():
			_registry_index[asset_id] = entry


## [S4.1] 为一份 Manifest placement 创建完整的参数化节点。
## 前置：已调用 index_registry。
## 副作用：在 parent 下创建子节点（模型/基本体 + 物理 + AnchorApproach）。
func create_placement(parent: Node, placement: Dictionary) -> Node3D:
	var semantic_id: String = placement.get("semantic_id", "unnamed")
	var asset_id: String = placement.get("asset_id", "")

	var container := Node3D.new()
	container.name = _semantic_id_to_node_name(semantic_id)
	parent.add_child(container)

	var asset_entry: Dictionary = _registry_index.get(asset_id, {})
	var geometry: Dictionary = asset_entry.get("geometry", {})
	var aabb_m: Array = geometry.get("aabb_m", [0.3, 0.3, 0.3])
	var aabb_vec := _array_to_vector3(aabb_m)
	var fit_mode: String = geometry.get("fit_mode", "uniform")
	var physics_role: String = asset_entry.get("roles", {}).get("physics", "none")
	var visual_role: String = asset_entry.get("roles", {}).get("visual", "clutter")
	var resource_path: String = asset_entry.get("resource_path", "")

	# Position container at manifest world position.
	var pos: Array = placement.get("position", [0.0, 0.0, 0.0])
	container.global_position = _array_to_vector3(pos)

	# Rotation.
	var rot: Array = placement.get("rotation_deg", [0.0, 0.0, 0.0])
	container.rotation_degrees = _array_to_vector3(rot)

	# Create visual node — either loaded model or parametric primitive.
	var visual: Node3D
	if resource_path.is_empty():
		visual = _create_primitive(aabb_vec, visual_role)
	else:
		visual = _create_from_model(resource_path, aabb_vec, fit_mode)
	visual.name = "Visual"

	# Add visual to container first (ensures it has a parent for reparent).
	container.add_child(visual)

	# Create physics body if needed.
	var physics_node: CollisionObject3D = null
	if physics_role != "none":
		if physics_role == "static":
			physics_node = StaticBody3D.new()
		else:
			physics_node = RigidBody3D.new()
			(physics_node as RigidBody3D).freeze = true
		physics_node.name = "PhysicsBody"
		physics_node.set_script(_INTERACTABLE_SCRIPT)
		physics_node.set("object_id", semantic_id)
		physics_node.set("object_name", placement.get("display_name", semantic_id))
		container.add_child(physics_node)
		# Now reparent the visual into the physics body.
		visual.reparent(physics_node, false)

		# Collision from declared AABB.
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape"
		var box := BoxShape3D.new()
		box.size = aabb_vec
		collision.shape = box
		physics_node.add_child(collision)
		_add_state_component(physics_node, semantic_id, visual_role, asset_entry)

	# Write metadata on the placement container.
	_write_metadata(container, asset_id, semantic_id, asset_entry)
	_add_role_components(container, visual_role, aabb_vec)

	# Create AnchorApproach at interaction_point.
	var anchor_parent: Node3D = physics_node if physics_node != null else container
	var anchor := _create_anchor(anchor_parent, placement)
	if physics_node != null:
		physics_node.set("interaction_point", anchor)

	return container


## [S3.2][S4.1] 为 Registry 声明 has_states 的物理对象附加通用状态组件。
func _add_state_component(
	physics_node: CollisionObject3D,
	semantic_id: String,
	visual_role: String,
	asset_entry: Dictionary,
) -> void:
	if not bool(asset_entry.get("capabilities", {}).get("has_states", false)):
		return
	var component := Node.new()
	component.name = "GeneratedObjectState"
	component.set_script(_GENERATED_STATE_SCRIPT)
	physics_node.add_child(component)
	component.configure(semantic_id, visual_role)
	var affordances: Array = asset_entry.get("capabilities", {}).get("affordances", [])
	if "change_channel" in affordances:
		var glow := OmniLight3D.new()
		glow.name = "TVScreenGlow"
		glow.position = Vector3(0.0, 0.35, 0.2)
		glow.light_color = Color(0.42, 0.72, 1.0)
		glow.light_energy = 0.0
		glow.omni_range = 2.4
		glow.visible = false
		physics_node.get_parent().add_child(glow)


## [S4.2] 根据视觉角色添加轻量运行时组件；灯具自动获得暖色局部光。
func _add_role_components(
	container: Node3D, visual_role: String, bounds: Vector3
) -> void:
	if visual_role != "lighting":
		return
	var light := OmniLight3D.new()
	light.name = "GeneratedWarmLight"
	light.position = Vector3(0.0, bounds.y * 0.35, 0.0)
	light.light_color = Color(1.0, 0.72, 0.43)
	light.light_energy = 1.15
	light.omni_range = 4.0
	light.shadow_enabled = true
	container.add_child(light)


## [S4.1] 从 Registry resource_path 加载并实例化模型，缩放到声明 AABB。
## 保持图片比例，将测量到的 AABB 中心移到局部 (0,0,0)。
## 副作用：缩放并平移实例节点。
func _create_from_model(
	resource_path: String, target_size: Vector3, fit_mode: String
) -> Node3D:
	var packed := load(resource_path) as PackedScene
	if packed == null:
		return _create_primitive(target_size, "decor")

	var instance: Node3D = packed.instantiate()
	var visual_root := Node3D.new()
	visual_root.add_child(instance)

	# Measure local bounds (using accumulated transforms, works without scene tree).
	var actual := _compute_bounds(instance)
	if actual.size.x > 0.001 and actual.size.y > 0.01 and actual.size.z > 0.001:
		var scale_factor := Vector3(
			target_size.x / actual.size.x,
			target_size.y / actual.size.y,
			target_size.z / actual.size.z,
		)
		var applied_scale := scale_factor
		if fit_mode != "axis":
			var uniform := minf(minf(scale_factor.x, scale_factor.y), scale_factor.z)
			applied_scale = Vector3(uniform, uniform, uniform)
		instance.scale = applied_scale
		instance.position = -actual.get_center() * applied_scale

	return visual_root


## [S4.1] 用声明 AABB 创建指定颜色的参数化 BoxMesh 基本体。
## 网格中心位于局部 (0,0,0)，placement 容器的全局位置就是模型中心。
func _create_primitive(size: Vector3, visual_role: String) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh_instance.mesh = box_mesh

	var material := StandardMaterial3D.new()
	var color: Color = _ROLE_COLORS.get(visual_role, _FALLBACK_COLOR)
	material.albedo_color = color
	material.roughness = 0.8
	mesh_instance.set_surface_override_material(0, material)

	return mesh_instance


## [S4.1] 在 placement 容器上写元数据（asset_id, semantic_id, roles, provenance）。
func _write_metadata(container: Node3D, asset_id: String, semantic_id: String, asset_entry: Dictionary) -> void:
	container.set_meta("asset_id", asset_id)
	container.set_meta("semantic_id", semantic_id)
	container.set_meta("roles", asset_entry.get("roles", {}))
	container.set_meta("capabilities", asset_entry.get("capabilities", {}))
	var provenance: Dictionary = asset_entry.get("provenance", {})
	container.set_meta("provenance", provenance)
	container.set_meta("visual_role", asset_entry.get("roles", {}).get("visual", "unknown"))
	container.set_meta("physics_role", asset_entry.get("roles", {}).get("physics", "none"))


## [S4.1] 在世界坐标 interaction_point 处创建 AnchorApproach 标记节点。
func _create_anchor(container: Node3D, placement: Dictionary) -> Marker3D:
	var ip: Array = placement.get("interaction_point", [])
	if ip.size() < 3:
		return null
	var world_ip := _array_to_vector3(ip)
	var anchor := Marker3D.new()
	anchor.name = "AnchorApproach"
	container.add_child(anchor)
	anchor.global_position = world_ip
	return anchor


## [S4.1] 递归计算节点以自身为根的子树的联合包围盒（局部空间）。
## 对任意深度的 Node3D 嵌套，累积子节点 transform 变换。
func _compute_bounds(node: Node3D) -> AABB:
	var bounds := AABB()
	var found := false
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh != null:
			var child_bounds: AABB = child.transform * child.get_aabb()
			bounds = child_bounds if not found else bounds.merge(child_bounds)
			found = true
		elif child is Node3D:
			# Recurse and apply child transform to convert from child-local to node-local space.
			var child_local_bounds: AABB = _compute_bounds(child)
			if child_local_bounds.size != Vector3.ZERO:
				var child_bounds: AABB = child.transform * child_local_bounds
				bounds = child_bounds if not found else bounds.merge(child_bounds)
				found = true
	return bounds if found else AABB(Vector3.ZERO, Vector3.ONE * 0.01)


## [S4.1] 安全地将 Array[3] 转换为 Vector3，默认零。
func _array_to_vector3(arr: Array) -> Vector3:
	if arr.size() < 3:
		return Vector3.ZERO
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


## [S2.1][S4.1] 将稳定 snake_case 语义 ID 转为兼容场景公共路径的 PascalCase。
## 转换不依赖具体资产或房间，因此新模型无需增加代码分支。
func _semantic_id_to_node_name(semantic_id: String) -> String:
	var node_name := ""
	for token in semantic_id.split("_"):
		if token.length() <= 2:
			node_name += token.to_upper()
		else:
			node_name += token.left(1).to_upper() + token.substr(1)
	return node_name
