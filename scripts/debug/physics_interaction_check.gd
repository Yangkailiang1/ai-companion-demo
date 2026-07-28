# Roadmap: C4.1, C4.4, S3.3
# Responsibility: 验证角色/家具碰撞、刚体拿取投掷、灯光状态和新增语义物体。
# Tests: 本文件为 Godot headless 运行时验收。

extends SceneTree

const ROOM_PATH := "WorldRoot/LivingRoom"

var _failed := false


func _init() -> void:
	call_deferred("_run")


## [C4.1][C4.4][S3.3] 组合验证物理世界与角色交互闭环。
func _run() -> void:
	root.get_node("ExperienceModeManager").enter_performance_mode()
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var room := scene.get_node(ROOM_PATH)
	_verify_character_colliders()
	_verify_scene_colliders(room)
	await _verify_rigid_body_interactions(room)
	_verify_new_affordances(room)
	_verify_room_lights(room)
	if not _failed:
		print("PHYSICS_INTERACTION_PASS agents=%d semantic_objects=%d" % [
			get_nodes_in_group("agents").size(),
			root.get_node("SemanticWorld").objects.size(),
		])
	root.get_node("AutonomousBehaviorSystem").set_scheduler_enabled(false)
	scene.free()
	quit(1 if _failed else 0)


## [C4.1] 每个角色必须有启用的胶囊碰撞和 CarryAnchor。
func _verify_character_colliders() -> void:
	var agents := get_nodes_in_group("agents")
	_assert(agents.size() >= 2, "no character agents found")
	for agent in agents:
		var agent_id := String(agent.get("agent_name"))
		var collision := agent.get_node_or_null("AgentCollision") as CollisionShape3D
		_assert(collision != null and not collision.disabled, "%s collider missing" % agent_id)
		_assert(collision.shape is CapsuleShape3D, "%s collider is not capsule" % agent_id)
		_assert(agent.get_node_or_null("CarryAnchor") != null, "%s carry anchor missing" % agent_id)
		_assert(int(agent.collision_layer) == 2, "%s must use character collision layer" % agent_id)
		_assert(int(agent.collision_mask) == 1, "%s must retain world collision" % agent_id)


## [C4.1][S3.3] 地板、墙、家具和小物体必须有物理形状。
func _verify_scene_colliders(room: Node) -> void:
	for path in [
		"FloorPhysics/FloorCollision",
		"WallBackPhysics/WallBackCollision",
		"WallLeftPhysics/WallLeftCollision",
		"WallRightPhysics/WallRightCollision",
		"Sofa/SofaCollision",
		"TV/TVCollision",
		"CoffeeTable/CoffeeTableCollision",
		"Book/BookCollision",
		"MilkTea/MilkTeaCollision",
		"Plant/PlantCollision",
		"Bookshelf/BookshelfCollision",
		"RoomLightSwitch/SwitchCollision",
	]:
		var shape := room.get_node_or_null(path) as CollisionShape3D
		_assert(shape != null and shape.shape != null and not shape.disabled, "missing collider %s" % path)


## [C4.4][C4.5] 验证书本拿起/放下，以及奶茶受冲量投掷后由物理引擎移动。
## 先移动角色至拿取距离内，再执行 pick_up。
func _verify_rigid_body_interactions(room: Node) -> void:
	var book := room.get_node("Book")
	var main := room.get_node("Agent")
	_assert(book.is_class("RigidBody3D") and bool(book.get("freeze")), "book must start frozen")

	# 走近书本以满足 2.0m 距离合约
	main.global_position = book.global_position + Vector3(0.5, 0, 0.5)
	await process_frame
	_assert(main.global_position.distance_to(book.global_position) <= 2.0,
		"agent must be within pickup distance")

	var picked: Dictionary = book.perform_interaction("pick_up", "main_agent")
	_assert(bool(picked.get("success", false)), "book pick_up failed")
	_assert(book.get_parent() == main.get_node("CarryAnchor"), "book did not attach to main hand")
	_assert(int(book.collision_layer) == 0, "carried book collision stayed active")
	var placed: Dictionary = book.perform_interaction("put_down", "main_agent")
	_assert(bool(placed.get("success", false)), "book put_down failed")
	_assert(book.get_parent() == room and not bool(book.get("freeze")), "book physics did not resume")
	await create_timer(0.55).timeout
	_assert(book.global_position.y > -0.05, "book fell through physical floor")

	var cup := room.get_node("MilkTea")
	var jue := room.get_node("JueAgent")

	# 走近奶茶
	jue.global_position = cup.global_position + Vector3(0.5, 0, 0.5)
	await process_frame

	_assert(bool(cup.perform_interaction("pick_up", "jue_agent").get("success", false)), "cup pick_up failed")
	var release_position: Vector3 = cup.global_position
	_assert(bool(cup.perform_interaction("throw", "jue_agent").get("success", false)), "cup throw failed")
	await create_timer(0.45).timeout
	_assert(cup.global_position.distance_to(release_position) > 0.2, "physics impulse did not move cup")
	_assert(cup.global_position.y > -0.1, "cup fell through physical floor")


## [S3.3][D2] 新家具必须注册真实可执行 affordance。
func _verify_new_affordances(room: Node) -> void:
	var semantic := root.get_node("SemanticWorld")
	for object_id in ["coffee_table", "bookshelf", "room_lights"]:
		var object = semantic.get_object(object_id)
		_assert(object != null and object.godot_node != null, "%s was not registered" % object_id)
	var inspected: Dictionary = room.get_node("CoffeeTable").perform_interaction("inspect", "main_agent")
	var browsed: Dictionary = room.get_node("Bookshelf").perform_interaction("browse", "jue_agent")
	_assert(bool(inspected.get("handled", false)), "coffee table inspect failed")
	_assert(bool(browsed.get("handled", false)), "bookshelf browse failed")


## [S3.3] 壁灯交互必须同步语义状态、真实光源和发光网格。
func _verify_room_lights(room: Node) -> void:
	var switch := room.get_node("RoomLightSwitch")
	_assert(bool(switch.perform_interaction("turn_off", "main_agent").get("success", false)), "lights off failed")
	_assert(is_zero_approx(room.get_node("LeftSconceLight").light_energy), "left light stayed on")
	_assert(not room.get_node("LeftWallLampGlow").visible, "lamp glow stayed visible")
	_assert(bool(switch.perform_interaction("dim", "main_agent").get("success", false)), "lights dim failed")
	_assert(room.get_node("RightSconceLight").light_energy > 0.1, "dim light has no energy")


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("PHYSICS_INTERACTION_FAIL: %s" % message)
