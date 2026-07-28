# Verifies: C2.1, C2.3, C2.4
# Covers: distance-driven gait, blocked phase freeze, native clip speed sync,
# Jue/Q semantic leg coverage, forward movement and idle recovery.

extends SceneTree

const LocomotionPoseClass = preload(
	"res://scripts/characters/character_locomotion_pose.gd"
)

var _failed := false


## [C2.3][C2.4] 运行纯步态合同与场景角色行走闭环。
func _init() -> void:
	call_deferred("_run")


## [C2.1][C2.3][C2.4] 加载客厅并依次验证程序化与原生行走后端。
func _run() -> void:
	_verify_distance_driven_pose()
	root.get_node("ExperienceModeManager").enter_performance_mode()
	var room := (load("res://scenes/living_room.tscn") as PackedScene).instantiate()
	root.add_child(room)
	await process_frame
	await process_frame
	await _wait_for_navigation(room)
	await _verify_jue_gait(room)
	await _verify_penguin_clip_sync(room)
	await _verify_local_q_gaits(room)
	if not _failed:
		print("LOCOMOTION_QUALITY_PASS")
	room.queue_free()
	await process_frame
	quit(1 if _failed else 0)


## [C4.1][T4.5] 等待 NavMesh 同步，避免把地图初始化误判为步态失败。
func _wait_for_navigation(room: Node) -> void:
	var navigation_agent := room.get_node("Agent/NavigationAgent3D") as NavigationAgent3D
	var navigation_map := navigation_agent.get_navigation_map()
	for _frame in range(90):
		if NavigationServer3D.map_get_iteration_id(navigation_map) >= 2:
			return
		await physics_frame
	_assert(false, "NavigationMesh did not synchronize")


## [C2.3][C2.4] 证明相位由米制位移推进，静止时相位冻结且姿势淡出。
func _verify_distance_driven_pose() -> void:
	var gait = LocomotionPoseClass.new()
	gait.configure({"stride_meters": 1.0, "blend_seconds": 0.1})
	var overlay := {"oscillate_degrees": {"left_upper_leg": [20, 0, 0]}}
	gait.sample(0.05, Vector3.ZERO, true, overlay)
	gait.sample(0.05, Vector3(0.25, 0, 0), true, overlay)
	var moving_phase: float = gait.get_phase_radians()
	_assert(moving_phase > 1.4 and moving_phase < 1.7, "gait phase is not distance-driven")
	for _index in range(4):
		gait.sample(0.05, Vector3(0.25, 0, 0), true, overlay)
	_assert(is_equal_approx(gait.get_phase_radians(), moving_phase), "blocked gait kept cycling")
	_assert(gait.get_blend_weight() <= 0.001, "blocked gait did not blend to baseline")


## [C2.1][C2.3] 验证诀的 22 关节腿链和实际导航步态。
func _verify_jue_gait(room: Node) -> void:
	var actor := room.get_node("JueAgent") as CharacterBody3D
	var overlay := actor.get_node("CharacterPoseOverlay")
	var bus := root.get_node("MessageBus")
	var bones: Dictionary = overlay.get_resolved_bone_names()
	for semantic_name in [
		"left_upper_leg", "left_lower_leg", "left_foot",
		"right_upper_leg", "right_lower_leg", "right_foot",
	]:
		_assert(bones.has(semantic_name), "Jue missing locomotion bone: %s" % semantic_name)
	var start := actor.global_position
	var target := RoomNavigation.new().get_waypoint("perimeter_w")
	bus.performance_cue.emit("walk", {"agent_id": "jue_agent", "source": "quality_test"})
	actor.move_to_position(target)
	var maximum_blend := 0.0
	for _frame in range(24):
		await physics_frame
		maximum_blend = maxf(maximum_blend, float(overlay._locomotion_pose.get_blend_weight()))
	_assert(overlay.get_current_overlay_gesture() == "walk", "Jue did not enter walk overlay")
	_assert(maximum_blend > 0.001, "Jue gait did not blend in while moving: blend=%.3f distance=%.3f"
		% [maximum_blend, actor.global_position.distance_to(start)])
	_assert(actor.global_position.distance_to(start) > 0.2, "Jue did not move")
	_assert(actor.global_transform.basis.y.normalized().dot(Vector3.UP) > 0.9, "Jue tipped over")
	actor.cancel_movement("test_complete")
	await process_frame
	_assert(overlay.get_current_overlay_gesture() == "idle", "Jue did not return to idle")


## [C2.1][C2.4] 验证企鹅原生 walk 剪辑的速度范围与停止复位。
func _verify_penguin_clip_sync(room: Node) -> void:
	var actor := room.get_node("Agent") as CharacterBody3D
	var player := actor.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var start := actor.global_position
	actor.move_to_position(RoomNavigation.new().get_waypoint("perimeter_nw"))
	var observed_synced_scale := false
	for _frame in range(12):
		await physics_frame
		if player.speed_scale >= 0.62 and player.speed_scale <= 1.36:
			observed_synced_scale = true
	_assert(player.current_animation == "walk", "penguin native walk clip did not start")
	_assert(observed_synced_scale, "walk speed scale never entered profile bounds")
	actor.cancel_movement("test_complete")
	await process_frame
	await process_frame
	_assert(player.current_animation == "idle", "penguin did not return to idle clip")
	_assert(is_equal_approx(player.speed_scale, 1.0), "non-walk playback speed did not reset")


## [C2.3][C6.2] 可选本地 Q 角色必须解析腿链并响应统一 walk/idle cue。
func _verify_local_q_gaits(room: Node) -> void:
	var spawner := room.get_node("LocalCharacterSpawner")
	var bus := root.get_node("MessageBus")
	for actor in spawner.get_children():
		if not actor is CharacterBody3D:
			continue
		var overlay := actor.get_node("CharacterPoseOverlay")
		var bones: Dictionary = overlay.get_resolved_bone_names()
		_assert(bones.has("left_lower_leg") and bones.has("right_foot"),
			"%s missing Q gait bones" % actor.name)
		bus.performance_cue.emit("walk", {
			"agent_id": String(actor.agent_name), "source": "quality_test",
		})
		await process_frame
		_assert(overlay.get_current_overlay_gesture() == "walk", "%s did not walk" % actor.name)
		bus.performance_cue.emit("idle", {
			"agent_id": String(actor.agent_name), "source": "quality_test",
		})
		await process_frame
		_assert(overlay.get_current_overlay_gesture() == "idle", "%s did not idle" % actor.name)


## [T4.5] 记录稳定失败并允许场景清理完成。
func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("LOCOMOTION_QUALITY_FAIL: " + message)
