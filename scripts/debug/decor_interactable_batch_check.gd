# Verifies: S3.7, T2.1, T2.2, C4.3
# Covers: window, back_wall_shelf, leaf_art — static decor interactables
# Checks: scene proxy binding, collision, approach/look anchors, NavMesh safety,
# descriptor binding, affordance execution, inspect state change, save round-trip.

extends SceneTree

const ROOM_PATH := "WorldRoot/LivingRoom"
const DECOR_IDS := ["window", "back_wall_shelf", "leaf_art"]
const NODE_NAMES := ["WindowProxy", "BackWallShelfProxy", "LeafArtProxy"]

var _failed := false


## [T4.5] 延迟到 Autoload 和场景加载完成后检查。
func _init() -> void:
	call_deferred("_run")


## [S3.7][T2.1][T2.2] 对三件静态装饰交互物执行完整合同检查。
func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	for i in range(DECOR_IDS.size()):
		_verify_one(DECOR_IDS[i], NODE_NAMES[i], scene)

	for object_id in DECOR_IDS:
		_verify_spec_file(object_id)

	if not _failed:
		print("DECOR_INTERACTABLE_BATCH_PASS ids=%s" % str(DECOR_IDS))

	root.get_node("AutonomousBehaviorSystem").set_scheduler_enabled(false)
	scene.free()
	await process_frame
	quit(1 if _failed else 0)


## [S3.7][C4.3] 对单个装饰物执行场景合同、语义绑定、交互和存档检查。
func _verify_one(object_id: String, node_name: String, scene: Node) -> void:
	var path := "%s/%s" % [ROOM_PATH, node_name]
	var proxy: StaticBody3D = scene.get_node_or_null(path) as StaticBody3D
	if proxy == null:
		_assert(false, "%s scene proxy %s missing" % [object_id, node_name])
		return
	_verify_scene_contract(proxy, object_id)
	_verify_semantic_contract(proxy, object_id)
	_verify_affordance_and_save(proxy, object_id)


## [S3.7][C4.3] 验证代理节点是 StaticBody3D、有碰撞体和 approach/look 锚点，
## 且 approach 锚点位于安全可导航范围。
func _verify_scene_contract(proxy: StaticBody3D, object_id: String) -> void:
	_assert(proxy is StaticBody3D, "%s must be StaticBody3D" % object_id)

	var collision := proxy.get_node_or_null("%sCollision" % proxy.name) as CollisionShape3D
	_assert(collision != null and collision.shape != null,
		"%s collision shape missing" % object_id)

	for anchor_name in ["AnchorApproach", "AnchorLook"]:
		var node: Marker3D = proxy.get_node_or_null(anchor_name) as Marker3D
		_assert(node != null, "%s %s missing" % [object_id, anchor_name])

	var approach: Vector3 = proxy.get_anchor("approach")
	var nav := RoomNavigation.new()
	_assert(nav.is_walkable_position(approach),
		"%s approach (%s) is not walkable" % [object_id, approach])
	_assert(approach.distance_to(proxy.global_position) >= 0.75,
		"%s approach leaves no standing clearance" % object_id)

	# 墙位于负 Z 边界，look 锚点应从墙面略向房间内（Z 增大）偏移。
	var look: Vector3 = proxy.get_anchor("look")
	_assert(look.z >= proxy.global_position.z,
		"%s look anchor should be in front of wall plane" % object_id)


## [T2.1][T2.2] 验证语义世界描述符与场景节点双向绑定。
func _verify_semantic_contract(proxy: StaticBody3D, object_id: String) -> void:
	var semantic := root.get_node("SemanticWorld")
	var descriptor = semantic.get_object(object_id)
	_assert(descriptor != null, "%s scene_config descriptor missing" % object_id)
	_assert(descriptor.godot_node == proxy, "%s descriptor not bound to scene node" % object_id)
	_assert("inspect" in descriptor.affordances, "%s inspect affordance missing" % object_id)
	_assert("look_at" in descriptor.affordances, "%s look_at affordance missing" % object_id)

	var declared_license := String(descriptor.properties.get("license", ""))
	_assert(declared_license == "Project-authored",
		"%s license metadata missing or wrong: %s" % [object_id, declared_license])

	_assert(semantic.can_interact(object_id, "inspect"),
		"%s inspect not allowed by semantic check" % object_id)
	_assert(semantic.can_interact(object_id, "look_at"),
		"%s look_at not allowed by semantic check" % object_id)

	var descriptor_ip: Vector3 = descriptor.interaction_point
	var approach_ip: Vector3 = proxy.get_anchor("approach")
	_assert(descriptor_ip.distance_to(approach_ip) < 0.15,
		"%s scene_config interaction_point disagrees with approach anchor" % object_id)


## [S3.7][X1.1] 验证 inspect 会产生语义状态变化，且保存/恢复维持一致性。
func _verify_affordance_and_save(proxy: StaticBody3D, object_id: String) -> void:
	var semantic := root.get_node("SemanticWorld")
	var original_state := String(semantic.get_object(object_id).state)

	var result: Dictionary = proxy.perform_interaction("inspect", "main_agent")
	_assert(bool(result.get("handled", false)), "%s inspect was not handled" % object_id)
	_assert(bool(result.get("success", true)),
		"%s inspect returned failure: %s" % [object_id, result.get("reason", "unknown")])

	var inspected_state := String(semantic.get_object(object_id).state)
	_assert(inspected_state != original_state,
		"%s inspect produced no state change" % object_id)

	# look_at should not mutate state further (idempotent read)
	var look_result: Dictionary = proxy.perform_interaction("look_at", "main_agent")
	_assert(bool(look_result.get("handled", false)), "%s look_at was not handled" % object_id)

	# 检查保存往返
	var saved: Dictionary = semantic.export_save_state()
	_assert(saved.has(object_id), "%s missing from save export" % object_id)
	semantic.update_object_state(object_id, "临时测试状态_%s" % object_id)
	semantic.import_save_state(saved)
	var restored_state := String(semantic.get_object(object_id).state)
	_assert(restored_state == inspected_state,
		"%s save round-trip failed: expected '%s', got '%s'" % [object_id, inspected_state, restored_state])


## [S3.7] 验证 data/interactable_objects/ 下的 spec JSON 存在且字段完整。
func _verify_spec_file(object_id: String) -> void:
	var spec_path := "res://data/interactable_objects/%s.json" % object_id
	_assert(ResourceLoader.exists(spec_path), "%s spec file missing" % object_id)

	var file := FileAccess.open(spec_path, FileAccess.READ)
	_assert(file != null, "%s spec file unreadable" % object_id)
	var spec = JSON.parse_string(file.get_as_text())
	_assert(spec is Dictionary, "%s spec is not valid JSON" % object_id)
	_assert(spec.get("schema_version", 0) == 1, "%s schema_version wrong" % object_id)
	var spec_obj: Dictionary = spec.get("object", {})
	_assert(spec_obj.get("id", "") == object_id, "%s spec id mismatch" % object_id)
	_assert(spec_obj.get("type", "") == "decor", "%s spec type not 'decor'" % object_id)
	var spec_scene: Dictionary = spec.get("scene", {})
	_assert(spec_scene.get("body_type", "") == "StaticBody3D", "%s body_type wrong" % object_id)
	_assert(spec_scene.has("anchors") and spec_scene["anchors"].has("approach"),
		"%s spec anchors missing" % object_id)


## [T4.5] 记录失败并标记测试不通过。
func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("DECOR_INTERACTABLE_BATCH_FAIL: " + message)
