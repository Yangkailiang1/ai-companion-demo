# Roadmap: C4.4, C4.5, S3.2
# Responsibility: 调用语义物体交互并仅在成功后应用需求/消耗效果；
#   不导航、不管理动作队列，也不选择 affordance。
# Collaborators: SemanticWorld, InteractableObject, WorldSimulator
# Tests: scripts/debug/action_failure_contract_check.gd

class_name ActionObjectInteractor
extends RefCounted

const ResultClass = preload("res://scripts/core/action_execution_result.gd")


## [C4.4][C4.5][S3.2] 执行物体 verb 并返回稳定结果；失败绝不应用成功效果。
func perform(object_id: String, verb: String, actor_id: String) -> Dictionary:
	if object_id.is_empty():
		return ResultClass.failure("object_id_missing", {"verb": verb})
	var semantic_world := _autoload("SemanticWorld")
	var object = semantic_world.get_object(object_id) if semantic_world != null else null
	if object == null:
		return ResultClass.failure("object_not_found", {"object_id": object_id, "verb": verb})
	if not is_instance_valid(object.godot_node):
		return ResultClass.failure("object_node_missing", {"object_id": object_id, "verb": verb})
	if not object.godot_node.has_method("perform_interaction"):
		return ResultClass.failure("interaction_handler_missing", {
			"object_id": object_id, "verb": verb,
		})
	var raw: Dictionary = object.godot_node.perform_interaction(verb, actor_id)
	var result := ResultClass.from_interaction(raw, {"object_id": object_id, "verb": verb})
	if not ResultClass.is_success(result):
		_release_failed_reservation(object.godot_node, actor_id)
		return result
	if _should_apply_effects(verb):
		_apply_object_effects(object, actor_id)
	if object.consumable and verb in ["drink", "eat"]:
		semantic_world.update_object_state(
			object_id,
			"已喝完" if verb == "drink" else "已吃完",
		)
	return result


## [C4.5] 失败后幂等释放调用者的物体预订，避免占用泄漏。
func _release_failed_reservation(object_node: Node, actor_id: String) -> void:
	if object_node.has_method("release_interaction"):
		object_node.release_interaction(actor_id)


## [C4.4][S3.2] 仅在物体交互成功后应用需求效果。
func _apply_object_effects(object, actor_id: String) -> void:
	var world_simulator := _autoload("WorldSimulator")
	if world_simulator == null:
		return
	for effect_key in object.effects:
		var need_type = _need_type(String(effect_key))
		if need_type != null:
			world_simulator.apply_effect(need_type, float(object.effects[effect_key]), actor_id)


## [C4.4][S3.2] 只有消费、使用和休息类 verb 产生需求效果。
func _should_apply_effects(verb: String) -> bool:
	return verb not in [
		"pick_up", "put_down", "throw", "look_at", "inspect", "place_item",
		"browse", "take_book", "put_book_back",
	]


## [S3.2] 把语义效果键映射为需求枚举；未知键返回 null。
func _need_type(effect_key: String):
	match effect_key:
		"hunger": return AffordanceTypes.NeedType.HUNGER
		"energy": return AffordanceTypes.NeedType.ENERGY
		"social": return AffordanceTypes.NeedType.SOCIAL
		"fun": return AffordanceTypes.NeedType.FUN
	return null


## [T4.2] Resolves runtime services without compile-time singleton identifiers.
func _autoload(singleton_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(singleton_name) if tree != null else null
