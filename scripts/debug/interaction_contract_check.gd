# Roadmap: C4.3, C4.4, C4.5
# Responsibility: 验证交互锚点回退、占用预订生命周期、并发争抢、超时清除和 pick_up 距离合约。
# Tests: 本文件为 Godot headless 运行时验收。

extends SceneTree

const ROOM_PATH := "WorldRoot/LivingRoom"

var _failed := false


## [C4.3][C4.5] 入口：延迟到首帧后运行交互合同测试。
func _init() -> void:
	call_deferred("_run")


## [C4.3][C4.5][S3.3] 顺序执行七个合同验收组。
func _run() -> void:
	root.get_node("ExperienceModeManager").enter_performance_mode()
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var room: Node = scene.get_node(ROOM_PATH)
	_test_anchor_fallback(room)
	_test_reservation_lifecycle(room)
	_test_contention(room)
	await _test_timeout_expiry(room)
	_test_far_pickup_rejection(room)
	await _test_near_pickup_and_release(room)
	await _test_released_state_clean(room)

	if not _failed:
		print("INTERACTION_CONTRACT_PASS anchors=6 reservation_ops=7")

	root.get_node("AutonomousBehaviorSystem").set_scheduler_enabled(false)
	scene.free()
	quit(1 if _failed else 0)


## [C4.3] 所有声明的锚点类型返回有效世界坐标，缺失时回退到交互点。
func _test_anchor_fallback(room: Node) -> void:
	var book: Node = room.get_node("Book")
	for anchor in ["approach", "look", "left_hand_grab", "right_hand_grab", "place"]:
		var pos: Vector3 = book.get_anchor(anchor)
		_assert(pos.length() > 0.01, "book anchor '%s' is near origin" % anchor)
		_assert(pos.y > -0.1, "book anchor '%s' below floor" % anchor)

	# sit on non-sittable object falls back to approach
	var sit_pos: Vector3 = book.get_anchor("sit")
	var approach_pos: Vector3 = book.get_anchor("approach")
	_assert(sit_pos.distance_to(approach_pos) < 0.01, "book sit fallback diverges from approach")

	# sofa fallback works
	var sofa: Node = room.get_node("Sofa")
	_assert(sofa.get_anchor("sit").length() > 0.01, "sofa sit anchor invalid")

	# missing grab anchor falls back to approach
	var sofa_grab: Vector3 = sofa.get_anchor("left_hand_grab")
	_assert(sofa_grab.distance_to(sofa.get_anchor("approach")) < 0.01,
		"sofa hand grab fallback diverges from approach")


## [C4.5] 完整的 reserve → commit → release → idempotent-release 生命周期。
func _test_reservation_lifecycle(room: Node) -> void:
	var book: Node = room.get_node("Book")

	var invalid: Dictionary = book.reserve_interaction("", 10.0)
	_assert(not bool(invalid.get("success", false))
		and invalid.get("reason", "") == "invalid_actor", "empty actor reservation must fail")

	# reserve
	var res: Dictionary = book.reserve_interaction("test_actor", 10.0)
	_assert(bool(res.get("success", false)), "initial reserve failed")

	# commit
	var com: Dictionary = book.commit_interaction("test_actor")
	_assert(bool(com.get("success", false)), "commit after reserve failed")

	# release (committed)
	var rel: Dictionary = book.release_interaction("test_actor")
	_assert(bool(rel.get("success", false)), "release after commit failed")

	# idempotent release (not reserved anymore)
	var rel2: Dictionary = book.release_interaction("test_actor")
	_assert(bool(rel2.get("success", false)), "idempotent release should succeed")

	# reserve-then-release without commit
	book.reserve_interaction("test_actor", 10.0)
	var rel3: Dictionary = book.release_interaction("test_actor")
	_assert(bool(rel3.get("success", false)), "release after reserve failed")


## [C4.5] 第二个角色争抢同一物体被拒绝，提供稳定原因 "occupied"。
func _test_contention(room: Node) -> void:
	var book: Node = room.get_node("Book")

	# actor_a reserves
	book.reserve_interaction("actor_a", 10.0)

	# actor_b tries to reserve → occupied
	var b_res: Dictionary = book.reserve_interaction("actor_b", 10.0)
	_assert(not bool(b_res.get("success", false)), "actor_b should not reserve contested object")
	_assert(b_res.get("reason", "") == "occupied",
		"wrong contention reason: %s" % b_res.get("reason"))

	# actor_a releases
	book.release_interaction("actor_a")

	# actor_b can now reserve
	var b_res2: Dictionary = book.reserve_interaction("actor_b", 10.0)
	_assert(bool(b_res2.get("success", false)), "actor_b should reserve after release")

	book.release_interaction("actor_b")


## [C4.5] 预订超时后自动清除，其他角色可以抢占。
func _test_timeout_expiry(room: Node) -> void:
	var cup: Node = room.get_node("MilkTea")

	cup.reserve_interaction("timed_actor", 0.1)
	await create_timer(0.25).timeout

	var res: Dictionary = cup.reserve_interaction("new_actor", 10.0)
	_assert(bool(res.get("success", false)), "reserve after timeout should succeed")

	cup.release_interaction("new_actor")


## [C4.4][C4.5] 超出距离阈值的 pick_up 被拒绝，
## 父节点、位置和碰撞层均不改变，占用/预订状态不变。
func _test_far_pickup_rejection(room: Node) -> void:
	var book: Node = room.get_node("Book")
	var main: Node3D = room.get_node("Agent") as Node3D

	var original_parent: Node = book.get_parent()
	var original_position: Vector3 = book.global_position
	var original_layer: int = int(book.collision_layer)
	var original_mask: int = int(book.collision_mask)
	var original_freeze: bool = bool(book.get("freeze"))

	# 先禁用自主调度和导航，防止角色被拉回
	if main.has_method("cancel_movement"):
		main.cancel_movement("test_setup")

	# 记录原始位置并移开角色
	var saved_pos: Vector3 = main.global_position
	main.global_position = Vector3(50, 0, 50)
	await process_frame
	await process_frame

	_assert(main.global_position.distance_to(book.global_position) > 2.0,
		"agent must be beyond pickup range (actual=%.2f)" % main.global_position.distance_to(book.global_position))

	var result: Dictionary = book.perform_interaction("pick_up", "main_agent")
	_assert(not bool(result.get("success", false)),
		"far pickup should fail (reason=%s, state=%s)" % [result.get("reason"), result.get("state", "")])
	_assert(result.get("reason", "") == "too_far",
		"far pickup reason should be 'too_far', got '%s'" % result.get("reason"))

	# 状态不变
	_assert(book.get_parent() == original_parent,
		"parent changed after failed far pickup")
	_assert(book.global_position.distance_to(original_position) < 0.01,
		"position changed after failed far pickup (delta=%.3f)" % book.global_position.distance_to(original_position))
	_assert(int(book.collision_layer) == original_layer,
		"collision layer changed after failed far pickup")
	_assert(int(book.collision_mask) == original_mask,
		"collision mask changed after failed far pickup")
	_assert(bool(book.get("freeze")) == original_freeze,
		"freeze state changed after failed far pickup")

	# 占用/预订状态不变
	_assert(book.get_reserved_by() == "",
		"reservation should be clear after failed far pickup (got '%s')" % book.get_reserved_by())
	_assert(book._carried_by == "",
		"carrier should be empty after failed far pickup (got '%s')" % book._carried_by)

	# 恢复角色位置
	main.global_position = saved_pos
	await process_frame


## [C4.4][C4.5] 近距离拿取成功：物体挂载到 CarryAnchor，碰撞关闭，占用已确认。
## 放下后恢复物理与空闲状态。
func _test_near_pickup_and_release(room: Node) -> void:
	var book: Node = room.get_node("Book")
	var main: Node3D = room.get_node("Agent") as Node3D

	# 走近
	main.global_position = book.global_position + Vector3(0.5, 0, 0.5)
	await process_frame
	var dist: float = main.global_position.distance_to(book.global_position)
	_assert(dist <= 2.0, "actor should be in pick_up range (dist=%.2fm)" % dist)

	# 拿取
	var picked: Dictionary = book.perform_interaction("pick_up", "main_agent")
	_assert(bool(picked.get("success", false)),
		"near pickup failed: %s" % picked.get("reason", "unknown"))
	_assert(book.get_parent() == main.get_node("CarryAnchor"),
		"book not attached to CarryAnchor after near pickup")
	_assert(int(book.collision_layer) == 0,
		"carried book collision layer should be zero")
	_assert(book.get_reserved_by() == "main_agent",
		"pickup should commit reservation (got '%s')" % book.get_reserved_by())
	_assert(book._carried_by == "main_agent",
		"carrier should be main_agent (got '%s')" % book._carried_by)

	# 放下
	var placed: Dictionary = book.perform_interaction("put_down", "main_agent")
	_assert(bool(placed.get("success", false)),
		"put_down failed: %s" % placed.get("reason", "unknown"))

	# 放下后状态恢复
	_assert(book.get_reserved_by() == "",
		"reservation should be clear after put_down")
	_assert(book._carried_by == "",
		"carrier should be empty after put_down")


## [C4.5] 释放后的物体可以被其他角色正常预订和交互。
func _test_released_state_clean(room: Node) -> void:
	var book: Node = room.get_node("Book")

	book.reserve_interaction("actor_c", 10.0)
	var res: Dictionary = book.reserve_interaction("actor_d", 10.0)
	_assert(not bool(res.get("success", false)),
		"actor_d should not reserve after actor_c")

	book.release_interaction("actor_c")

	var res2: Dictionary = book.reserve_interaction("actor_d", 10.0)
	_assert(bool(res2.get("success", false)),
		"actor_d should reserve after actor_c released")

	book.release_interaction("actor_d")


## [C4.3][C4.5] 记录合同断言失败，并让测试最终返回非零退出码。
func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("INTERACTION_CONTRACT_FAIL: %s" % message)
