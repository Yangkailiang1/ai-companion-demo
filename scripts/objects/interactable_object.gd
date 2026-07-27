# interactable_object.gd — 可交互物体（带 Affordance）
# 附在客厅场景中的每个物体节点上
# 在 SemanticWorld 中注册自身

extends StaticBody3D

@export var object_id: String = ""
@export var object_name: String = ""
@export var interaction_point: Marker3D

# 在 SemanticWorld 中的注册信息
var _registered: bool = false


func _ready():
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
	return ""
