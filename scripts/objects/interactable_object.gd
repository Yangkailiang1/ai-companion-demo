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
