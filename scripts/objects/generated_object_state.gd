# Roadmap: S3.2, S4.1, T2.2
# Responsibility: Provide generic stateful affordance feedback for generated
# objects; does not decide actions or branch on concrete model resource paths.
# Collaborators: InteractableObject, SemanticWorld, ParametricAssetFactory
# Tests: scripts/debug/world_location_loader_check.gd

class_name GeneratedObjectState
extends Node

var object_id := ""
var visual_role := ""


## [S4.1][T2.2] 绑定稳定语义 ID 与 Registry 视觉角色；不改变世界状态。
func configure(generated_object_id: String, generated_visual_role: String) -> void:
	object_id = generated_object_id
	visual_role = generated_visual_role


## [S3.2][T2.2] 执行生成物体的通用有状态 affordance 并同步可见反馈。
## 未支持动词返回 handled=false，让 InteractableObject 继续走通用降级。
func perform_interaction(verb: String, _actor_id: String = "") -> Dictionary:
	var semantic_world := _autoload("SemanticWorld")
	if semantic_world == null:
		return {"handled": true, "success": false, "reason": "semantic_world_missing"}
	match verb:
		"turn_on", "watch":
			return _set_state(semantic_world, "暖光已开启" if visual_role == "lighting" else "播放温馨节目", 1.15)
		"turn_off":
			return _set_state(semantic_world, "关闭", 0.0)
		"dim":
			return _set_state(semantic_world, "柔和夜灯", 0.28)
		"change_channel":
			return _set_state(semantic_world, "播放轻松动画", 1.0)
		"water":
			return _update_plant(semantic_world, 48.0, 5.0)
		"prune":
			return _update_plant(semantic_world, 0.0, 3.0)
	return {"handled": false}


## [S3.2] 更新语义状态并调节同一生成容器中的灯光；返回标准交互结果。
func _set_state(semantic_world: Node, state: String, light_energy: float) -> Dictionary:
	semantic_world.update_object_state(object_id, state)
	var container := get_parent().get_parent() as Node3D
	if container != null:
		for light_name in ["GeneratedWarmLight", "TVScreenGlow"]:
			for child in container.find_children(
				light_name, "OmniLight3D", true, false
			):
				var light := child as OmniLight3D
				light.light_energy = light_energy
				light.visible = light_energy > 0.01
	return {"handled": true, "success": true, "state": state}


## [S3.2][T2.2] 更新植物含水与健康属性，并给模型提供轻量枯萎缩放反馈。
func _update_plant(
	semantic_world: Node, moisture_delta: float, health_delta: float
) -> Dictionary:
	var descriptor = semantic_world.get_object(object_id)
	if descriptor == null:
		return {"handled": true, "success": false, "reason": "object_missing"}
	var properties: Dictionary = descriptor.properties.duplicate(true)
	var moisture := clampf(float(properties.get("moisture", 28.0)) + moisture_delta, 0.0, 100.0)
	var health := clampf(float(properties.get("health", 82.0)) + health_delta, 0.0, 100.0)
	properties["moisture"] = moisture
	properties["health"] = health
	var state := "严重缺水" if moisture <= 20.0 else ("需要浇水" if moisture <= 35.0 else "状态良好")
	semantic_world.update_object_properties(object_id, properties, state)
	_apply_organic_scale(health)
	return {"handled": true, "success": true, "state": state}


## [S3.2] 根据健康度缩放生成植物 Visual；缺失视觉时安全无操作。
func _apply_organic_scale(health: float) -> void:
	if visual_role != "organic":
		return
	var container := get_parent().get_parent() as Node3D
	var visual := container.find_child("Visual", true, false) as Node3D
	if visual != null:
		var factor := lerpf(0.78, 1.0, health / 100.0)
		visual.scale = Vector3.ONE * factor


## [T2.2] 通过 SceneTree 解析 Autoload，支持动态创建的状态组件。
func _autoload(singleton_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(singleton_name) if tree != null else null
