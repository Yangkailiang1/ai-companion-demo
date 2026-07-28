# Roadmap: C4.3, C4.4, C4.5
# Responsibility: 管理物体交互锚点查询、物理拿取/放下/投掷和占用预订生命周期；
#   不包含认知决策、自主调度或导航逻辑。
# Collaborators: SemanticWorld, InteractionReservation, CodifiedProfile
# Tests: scripts/debug/physics_interaction_check.gd, scripts/debug/interaction_contract_check.gd

extends PhysicsBody3D

@export var object_id: String = ""
@export var object_name: String = ""
@export var interaction_point: Marker3D

const PICK_UP_DISTANCE_THRESHOLD_METERS: float = 2.0
const _ReservationClass = preload("res://scripts/objects/interaction_reservation.gd")

# 在 SemanticWorld 中的注册信息
var _registered: bool = false
var _original_parent: Node
var _carried_by := ""
var _saved_collision_layer := 1
var _saved_collision_mask := 1
var _reservation = _ReservationClass.new()


func _ready():
	_original_parent = get_parent()
	_saved_collision_layer = collision_layer
	_saved_collision_mask = collision_mask
	# 等待所有 Autoload 就绪
	await get_tree().process_frame
	_register_in_semantic_world()


func _register_in_semantic_world():
	if object_id.is_empty(): return

	var obj = SemanticWorld.get_object(object_id)
	if obj:
		obj.godot_node = self
		_registered = true
		print("  [Scene] Registered: %s → %s" % [object_id, object_name])


func get_interaction_point() -> Vector3:
	if interaction_point:
		return interaction_point.global_position
	return global_position + Vector3(0, 0, -1.0)


func get_object_id() -> String:
	return object_id


## [C4.3][T2.1] 按名称查询交互锚点的世界坐标。
## 支持的锚点：approach, look, left_hand_grab, right_hand_grab, place, sit。
## 缺失可选锚点时使用确定性回退：手部锚点 → 另一只手 → approach → 物体中心。
func get_anchor(anchor_name: String) -> Vector3:
	var child := _find_anchor_child(anchor_name)
	if child != null:
		return child.global_position
	return _anchor_fallback(anchor_name)


## [C4.3] 查询命名为 Anchor<PascalCase> 的 Marker3D 子节点。
## 若不存在则返回 null，让调用方走回退链。
func _find_anchor_child(anchor_name: String) -> Marker3D:
	var suffix := ""
	match anchor_name:
		"approach":      suffix = "Approach"
		"look":          suffix = "Look"
		"left_hand_grab": suffix = "LeftHandGrab"
		"right_hand_grab": suffix = "RightHandGrab"
		"place":         suffix = "Place"
		"sit":           suffix = "Sit"
		_:               suffix = "Approach"
	return get_node_or_null("Anchor" + suffix) as Marker3D


## [C4.3] 缺失锚点的确定性回退。
## 手部锚点 → 另一只手 → approach → 交互点或物体中心。
func _anchor_fallback(anchor_name: String) -> Vector3:
	match anchor_name:
		"left_hand_grab":
			var right := get_node_or_null("AnchorRightHandGrab") as Marker3D
			if right: return right.global_position
		"right_hand_grab":
			var left := get_node_or_null("AnchorLeftHandGrab") as Marker3D
			if left: return left.global_position
	return get_interaction_point()


## [C4.5][S3.3] 预订此物体供指定角色使用（不涉及物理状态变化）。
## 重复预订同一角色仅刷新超时。返回 {success, reason}。
func reserve_interaction(actor_id: String, timeout_seconds: float) -> Dictionary:
	return _reservation.reserve(actor_id, timeout_seconds)


## [C4.5][S3.3] 确认预订，将占用固定。
## 只能由当前预订者调用。
func commit_interaction(actor_id: String) -> Dictionary:
	return _reservation.commit(actor_id)


## [C4.5][S3.3] 释放占用/预订，幂等。
## 未被预订时调用亦成功。
func release_interaction(actor_id: String) -> Dictionary:
	return _reservation.release(actor_id)


## [C4.5] 返回当前预订者 ID；未被预订时返回空字符串。
func get_reserved_by() -> String:
	return _reservation.get_reserved_by()


## [S3.2][D3] 先委托专用状态组件；否则执行语义世界声明的通用交互反馈。
## 这样 Planner 看到的 affordance 与导演实际可执行能力保持一致。
func perform_interaction(verb: String, actor_id: String = "") -> Dictionary:
	for child in get_children():
		if child.has_method("perform_interaction"):
			var result: Dictionary = child.perform_interaction(verb, actor_id)
			if bool(result.get("handled", false)):
				return result
	if not SemanticWorld.can_interact(object_id, verb):
		return {"handled": false}
	var physics_result := _perform_physics_interaction(verb, actor_id)
	if not physics_result.is_empty():
		return physics_result
	var new_state := _generic_interaction_state(verb, actor_id)
	if not new_state.is_empty():
		SemanticWorld.update_object_state(object_id, new_state)
	return {"handled": true, "state": new_state}


## [S3.2] 为没有专用组件的常见 affordance 提供可见、可保存的语义状态。
func _generic_interaction_state(verb: String, actor_id: String) -> String:
	var actor_name := CodifiedProfile.get_agent_display_name(actor_id)
	match verb:
		"sit":
			return "%s坐在这里" % actor_name
		"lie_down":
			return "%s正在休息" % actor_name
		"read":
			return "%s正在阅读" % actor_name
		"drink":
			return "已喝完"
		"pick_up":
			return "被%s拿起" % actor_name
		"put_down":
			return "已放回原处"
		"throw":
			return "被放到一边"
		"look_at":
			return SemanticWorld.get_object(object_id).state
		"browse":
			return "%s正在浏览书架" % actor_name
		"take_book":
			return "%s从书架取下一本书" % actor_name
		"put_book_back":
			return "%s把书放回书架" % actor_name
		"inspect":
			return "%s仔细查看了%s" % [actor_name, object_name]
		"place_item":
			return "%s在桌面放好了物品" % actor_name
	return ""


## [S3.3][C4.4] 对 RigidBody3D 执行真实拿取、放下和投掷。
func _perform_physics_interaction(verb: String, actor_id: String) -> Dictionary:
	if not is_class("RigidBody3D") or verb not in ["pick_up", "put_down", "throw"]:
		return {}
	var body := self as Node3D
	var actor := _find_agent(actor_id)
	if actor == null:
		return {"handled": true, "success": false, "reason": "actor_not_found"}
	match verb:
		"pick_up":
			return _pick_up_body(body, actor, actor_id)
		"put_down":
			return _release_body(body, actor, actor_id, false)
		"throw":
			return _release_body(body, actor, actor_id, true)
	return {}


## [C4.4][C4.5] 把冻结的物理物体挂到角色 CarryAnchor，并暂时关闭碰撞。
## 新增：距离校验（超过 PICK_UP_DISTANCE_THRESHOLD_METERS 返回 too_far）；
## 通过占用预订协议确保同一时刻只有一个角色持有物体。
func _pick_up_body(body: Node3D, actor: Node3D, actor_id: String) -> Dictionary:
	# 距离校验：不得隔空拿取
	var dist: float = actor.global_position.distance_to(body.global_position)
	if dist > PICK_UP_DISTANCE_THRESHOLD_METERS:
		return {"handled": true, "success": false, "reason": "too_far"}

	# 占用预订：防止并发争抢
	var reserve_result: Dictionary = _reservation.reserve(actor_id, 10.0)
	if not bool(reserve_result.get("success", false)):
		return {"handled": true, "success": false, "reason": reserve_result.get("reason", "occupied")}

	if not _carried_by.is_empty() and _carried_by != actor_id:
		_reservation.release(actor_id)
		return {"handled": true, "success": false, "reason": "occupied"}

	var anchor := actor.get_node_or_null("CarryAnchor") as Node3D
	if anchor == null:
		_reservation.release(actor_id)
		return {"handled": true, "success": false, "reason": "carry_anchor_missing"}
	body.set("freeze", true)
	body.set("linear_velocity", Vector3.ZERO)
	body.set("angular_velocity", Vector3.ZERO)
	body.collision_layer = 0
	body.collision_mask = 0
	body.reparent(anchor, false)
	body.transform = Transform3D.IDENTITY
	_carried_by = actor_id
	_reservation.commit(actor_id)
	var state := "被%s拿在手中" % CodifiedProfile.get_agent_display_name(actor_id)
	SemanticWorld.update_object_state(object_id, state)
	return {"handled": true, "success": true, "state": state}


## [C4.4][C4.5] 恢复物理模拟；投掷时沿角色正面施加冲量。
## 释放时同步清除占用预订。
func _release_body(
	body: Node3D,
	actor: Node3D,
	actor_id: String,
	throwing: bool,
) -> Dictionary:
	if _carried_by != actor_id:
		return {"handled": true, "success": false, "reason": "not_carried_by_actor"}
	var forward := actor.global_transform.basis.z.normalized()
	var release_position := actor.global_position + forward * 0.62 + Vector3.UP * 1.15
	body.reparent(_original_parent, true)
	body.global_position = release_position
	body.collision_layer = _saved_collision_layer
	body.collision_mask = _saved_collision_mask
	body.set("freeze", false)
	body.set("sleeping", false)
	body.set("linear_velocity", Vector3.ZERO)
	body.set("angular_velocity", Vector3.ZERO)
	if throwing:
		body.call("apply_central_impulse", forward * 2.8 + Vector3.UP * 1.45)
		body.call("apply_torque_impulse", Vector3(0.35, 0.2, -0.25))
	_carried_by = ""
	_reservation.release(actor_id)
	var state := "被%s抛出" if throwing else "由%s放在附近"
	state = state % CodifiedProfile.get_agent_display_name(actor_id)
	SemanticWorld.update_object_state(object_id, state)
	return {"handled": true, "success": true, "state": state}


## [C4.4] 按稳定 agent_id 查找场景角色。
func _find_agent(actor_id: String) -> Node3D:
	for node in get_tree().get_nodes_in_group("agents"):
		if String(node.get("agent_name")) == actor_id and node is Node3D:
			return node as Node3D
	return null
