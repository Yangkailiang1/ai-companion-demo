# Verifies: S3.6, T2.1, T2.2, C4.2, C4.3
# Covers: public GLTF -> scene instance -> collision -> anchors -> SemanticWorld ->
# affordance execution -> save round-trip.

extends SceneTree

const ROOM_PATH := "WorldRoot/LivingRoom"
const OBJECT_ID := "wall_art"
const MODEL_PATH := "res://assets/props/polyhaven/hanging_picture_frame_01/hanging_picture_frame_01_1k.gltf"

var _failed := false


## [T4.5] 延迟到 Autoload 和导入资源可用后运行。
func _init() -> void:
	call_deferred("_run")


## [S3.6][T2.1][T2.2] 验证公开 3D 物体接入的完整黄金流程。
func _run() -> void:
	_assert(ResourceLoader.exists(MODEL_PATH), "public GLTF import is missing")
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var object_node := scene.get_node("%s/WallArt" % ROOM_PATH)
	_verify_scene_contract(object_node)
	_verify_semantic_contract(object_node)
	_verify_affordance_and_save(object_node)
	_verify_license_manifest()
	if not _failed:
		print("INTERACTABLE_ASSET_PIPELINE_PASS object=%s model=%s" % [OBJECT_ID, MODEL_PATH])
	root.get_node("AutonomousBehaviorSystem").set_scheduler_enabled(false)
	scene.free()
	await process_frame
	quit(1 if _failed else 0)


## [S3.6][C4.3] 验证模型实例、碰撞体和 approach/look 锚点。
func _verify_scene_contract(object_node: Node3D) -> void:
	_assert(object_node is StaticBody3D, "interactable decor must use StaticBody3D")
	_assert(object_node.get_node_or_null("PictureFrameModel") != null, "GLTF model instance missing")
	var collision := object_node.get_node_or_null("PictureFrameCollision") as CollisionShape3D
	_assert(collision != null and collision.shape != null, "collision shape missing")
	for anchor_name in ["AnchorApproach", "AnchorLook"]:
		_assert(object_node.get_node_or_null(anchor_name) is Marker3D, "%s missing" % anchor_name)
	var approach: Vector3 = object_node.get_anchor("approach")
	_assert(RoomNavigation.new().is_safe_position(approach), "approach anchor is outside safe bounds")
	_assert(approach.distance_to(object_node.global_position) >= 0.75,
		"approach anchor leaves no standing clearance")


## [T2.1][T2.2] 验证语义描述与真实场景节点双向绑定。
func _verify_semantic_contract(object_node: Node3D) -> void:
	var semantic := root.get_node("SemanticWorld")
	var descriptor = semantic.get_object(OBJECT_ID)
	_assert(descriptor != null, "scene_config descriptor missing")
	_assert(descriptor.godot_node == object_node, "descriptor was not bound to scene node")
	_assert("inspect" in descriptor.affordances, "inspect affordance missing")
	_assert(descriptor.properties.get("license", "") == "CC0", "license metadata missing")
	_assert(descriptor.interaction_point.distance_to(object_node.get_anchor("approach")) < 0.1,
		"scene and semantic approach points disagree")


## [S3.6][X1.1] 验证交互状态变化会进入统一存档并可恢复。
func _verify_affordance_and_save(object_node: Node3D) -> void:
	var semantic := root.get_node("SemanticWorld")
	var original_state := String(semantic.get_object(OBJECT_ID).state)
	var result: Dictionary = object_node.perform_interaction("inspect", "main_agent")
	_assert(bool(result.get("handled", false)), "inspect was not handled")
	var inspected_state := String(semantic.get_object(OBJECT_ID).state)
	_assert(inspected_state != original_state, "inspect produced no semantic feedback")
	var saved: Dictionary = semantic.export_save_state()
	_assert(saved.has(OBJECT_ID), "object state missing from save export")
	semantic.update_object_state(OBJECT_ID, "测试临时状态")
	semantic.import_save_state(saved)
	_assert(String(semantic.get_object(OBJECT_ID).state) == inspected_state,
		"save round-trip did not restore object state")


## [O4.1][S3.6] 验证资产清单中记录来源、CC0 许可和相对入口名。
func _verify_license_manifest() -> void:
	var path := "res://assets/props/polyhaven/polyhaven_manifest.json"
	var entries = JSON.parse_string(FileAccess.get_file_as_string(path))
	var found := false
	for entry in entries if entries is Array else []:
		if String(entry.get("asset", "")) == "hanging_picture_frame_01":
			found = String(entry.get("license", "")) == "CC0"
			break
	_assert(found, "CC0 asset manifest entry missing")


## [T4.5] 记录稳定失败并允许资源清理。
func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("INTERACTABLE_ASSET_PIPELINE_FAIL: " + message)
