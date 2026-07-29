# Roadmap: S2.2
# Responsibility: One visible clickable portal for player room travel; handles
# visual, picking, hover, label and semantic registration. Does NOT select a
# target location or reference WorldLocationLoader.
# Collaborators: SemanticWorld, WorldPortalAssembler
# Tests: scripts/debug/world_travel_portal_check.gd

class_name WorldTravelPortal
extends Area3D

signal travel_requested(exit_id: String)
signal walkthrough_requested(exit_id: String)

const WOOD_COLOR := Color(0.50, 0.32, 0.15, 1.0)
const WOOD_HOVER_COLOR := Color(0.62, 0.40, 0.20, 1.0)
const WOOD_PRESS_COLOR := Color(0.40, 0.24, 0.10, 1.0)

var exit_id := ""
var location_id := ""
var portal_label := ""
var semantic_id := ""
var _material: StandardMaterial3D
var _requested := false
var _label_node: Label3D


## [S2.2] 使用已校验的 portal 数据显示门框、碰撞体和标签。
## 副作用：在场景树下创建 BoxMesh/StandardMaterial3D/Label3D，并在 SemanticWorld 注册。
## 未提供有效 exit_id 时不执行任何操作。
func configure(data: Dictionary) -> void:
	exit_id = String(data.get("exit_id", ""))
	location_id = String(data.get("location_id", ""))
	semantic_id = String(data.get("semantic_id", ""))
	portal_label = String(data.get("label", ""))
	if exit_id.is_empty() or semantic_id.is_empty():
		push_error("WorldTravelPortal: missing exit_id or semantic_id")
		return

	var position: Vector3 = _vec3(data.get("position", []), Vector3.ZERO)
	var rotation_deg: Vector3 = _vec3(data.get("rotation_deg", []), Vector3.ZERO)
	var size: Array = data.get("size", [1.25, 2.2])

	name = "Portal_" + semantic_id
	self.position = position
	rotation_degrees = rotation_deg

	_build_frame(size)
	_build_collision(size)
	_build_label()
	_register_semantic()
	input_ray_pickable = true
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	body_entered.connect(_on_body_entered)


## [S2.2] 构建暖木色门框：两根侧柱和一根横梁。
func _build_frame(size: Array) -> void:
	var width: float = float(size[0]) if size.size() >= 1 else 1.25
	var height: float = float(size[1]) if size.size() >= 2 else 2.2
	var post_thickness := 0.12
	var post_width := 0.10
	var beam_thickness := 0.12

	_material = StandardMaterial3D.new()
	_material.albedo_color = WOOD_COLOR
	_material.roughness = 0.7

	var frame := Node3D.new()
	frame.name = "Frame"
	add_child(frame)

	# Left post
	_add_box_mesh(frame, "PostLeft",
		Vector3(post_width, height, post_thickness),
		Vector3(-width * 0.5 + post_width * 0.5, 0.0, 0.0), _material)
	# Right post
	_add_box_mesh(frame, "PostRight",
		Vector3(post_width, height, post_thickness),
		Vector3(width * 0.5 - post_width * 0.5, 0.0, 0.0), _material)
	# Top beam
	_add_box_mesh(frame, "BeamTop",
		Vector3(width, beam_thickness, post_thickness),
		Vector3(0.0, height * 0.5 - beam_thickness * 0.5, 0.0), _material)
	_add_box_mesh(frame, "Threshold",
		Vector3(width, 0.06, 0.28),
		Vector3(0.0, -height * 0.5 + 0.03, 0.0), _material)
	var leaf := Node3D.new()
	leaf.name = "DoorLeafPivot"
	leaf.position = Vector3(-width * 0.5 + post_width, 0.0, 0.0)
	leaf.rotation_degrees.y = -24.0
	frame.add_child(leaf)
	_add_box_mesh(leaf, "DoorLeaf",
		Vector3(width * 0.72, height * 0.88, 0.07),
		Vector3(width * 0.36, -0.04, 0.0), _material)


## [S2.2] 添加单个盒子网格，附带指定材质。
func _add_box_mesh(parent: Node3D, node_name: String, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	mesh.set_surface_override_material(0, mat)
	parent.add_child(mesh)


## [S2.2] 添加覆盖整个门框的拾取形状。
func _build_collision(size: Array) -> void:
	var width: float = float(size[0]) if size.size() >= 1 else 1.25
	var height: float = float(size[1]) if size.size() >= 2 else 2.2
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "PortalCollision"
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, 0.35)
	collision_shape.shape = box
	collision_shape.position = Vector3.ZERO
	add_child(collision_shape)


## [S2.2] 创建门上方 3D 标签。
func _build_label() -> void:
	_label_node = Label3D.new()
	_label_node.name = "PortalLabel"
	_label_node.text = portal_label
	_label_node.font_size = 36
	_label_node.modulate = Color(1.0, 0.95, 0.8, 1.0)
	_label_node.outline_size = 2
	_label_node.position = Vector3(0.0, 1.42, 0.0)
	_label_node.billboard = 1
	_label_node.no_depth_test = true
	add_child(_label_node)


## [S2.2] 在 SemanticWorld 注册此入口为带 traverse 能力的可交互点。
## 副作用：通过 SemanticWorld 公共生成物体 API 注册语义条目。
func _register_semantic() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var semantic := tree.root.get_node_or_null("SemanticWorld")
	if semantic == null or not semantic.has_method("upsert_generated_object"):
		return
	semantic.upsert_generated_object({
		"semantic_id": semantic_id,
		"display_name": str("门口：", portal_label),
		"description": str("通往", portal_label, "的温暖木门"),
		"initial_state": "可以通行",
		"affordances": ["traverse"],
		"position": [global_position.x, global_position.y, global_position.z],
		"interaction_point": [global_position.x, global_position.y, global_position.z],
		"needs_proximity": true,
		"properties": {"location_id": location_id, "exit_id": exit_id},
		"location_id": location_id,
	}, self)


## [S2.5][X1.2] 常驻房间重新激活或语义世界重置后恢复门的语义绑定。
func refresh_semantic_registration() -> void:
	_register_semantic()


## [S2.2][P2.3] 玩家身体走进门区时请求连续房间切换；AI 仍使用语义交互。
func _on_body_entered(body: Node3D) -> void:
	if body is PlayerFirstPersonController and not _requested:
		walkthrough_requested.emit(exit_id)


## [S2.2] 左键点击时发出 travel_requested；防止重复激活。
## 已在退役或被释放时静默忽略。
func _input_event(_camera: Camera3D, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_request_travel()


## [S2.2] 鼠标进入时提亮门框颜色。
func _on_mouse_entered() -> void:
	if _material == null or _requested:
		return
	_material.albedo_color = WOOD_HOVER_COLOR


## [S2.2] 鼠标离开时恢复门框颜色。
func _on_mouse_exited() -> void:
	if _material == null or _requested:
		return
	_material.albedo_color = WOOD_COLOR


## [S2.2][C5.3] 玩家空 actor_id 时切换活动房间；AI actor_id 只迁移该居民。
## 两条路径共享地点图校验，但 AI 迁移不会移动 PlayerBody 或玩家镜头。
func perform_interaction(verb: String, actor_id: String = "") -> Dictionary:
	if verb != "traverse":
		return {"handled": false}
	if _requested or not is_inside_tree():
		return {"handled": true, "success": false, "reason": "stale"}
	if not actor_id.is_empty():
		var loader := get_parent().get_parent()
		if loader == null or not loader.has_method("transfer_agent_via"):
			return {"handled": true, "success": false, "reason": "loader_missing"}
		var transferred := bool(loader.transfer_agent_via(
			actor_id, location_id, exit_id
		))
		return {
			"handled": true,
			"success": transferred,
			"reason": "" if transferred else "resident_transfer_rejected",
		}
	var loader := get_parent().get_parent()
	if (
		loader != null
		and loader.has_method("get_active_location")
		and loader.get_active_location() != get_parent()
	):
		return {"handled": true, "success": false, "reason": "inactive_location"}
	_request_travel()
	return {"handled": true, "success": true}


## [S2.2] 在地点退役宽限期开始前禁用拾取和旅行请求。
## 副作用：当前门廊永久进入 stale 状态。
func deactivate() -> void:
	_requested = true
	input_ray_pickable = false
	monitoring = false
	monitorable = false


## [S2.5] 已加载房间重新激活时解除一次性点击锁。
func reactivate() -> void:
	_requested = false
	input_ray_pickable = true
	monitoring = true
	monitorable = true
	if _material != null:
		_material.albedo_color = WOOD_COLOR


## [S2.2] 返回此入口是否已不可用。
func is_stale() -> bool:
	return _requested or not is_inside_tree() or is_queued_for_deletion()


## [S2.2] 统一处理鼠标与语义交互旅行，只允许首次请求。
func _request_travel() -> void:
	if _requested or not is_inside_tree():
		return
	_requested = true
	if _material != null:
		_material.albedo_color = WOOD_PRESS_COLOR
	travel_requested.emit(exit_id)


## [S2.2] 将 JSON 三元数组转换为 Vector3；纯函数。
func _vec3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback
