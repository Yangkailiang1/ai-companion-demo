# Verifies: S2.1, S4.1, C6.2
# Covers: explicit legacy -> parametric switch -> invalid-mode fallback.

extends SceneTree

var _failed := false


## [S2.1] 延迟执行地点切换合同，避免 Autoload 初始化竞态。
func _init() -> void:
	call_deferred("_run")


## [S2.1][S4.1][C6.2] 验证主场景两种模式、生成报告与角色路径兼容。
func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var world_root := scene.get_node("WorldRoot") as WorldLocationLoader
	# [X1.2] 自动存档可能恢复参数化地点；模式合同测试必须先显式归一到 legacy。
	_assert(world_root.switch_location("legacy") == "legacy", "legacy switch failed")
	_assert(world_root.has_node("LivingRoom/Sofa"), "legacy room path missing")
	_assert(
		world_root.get_node("LivingRoom/Agent").scene_file_path
			== "res://scenes/characters/main_agent.tscn",
		"legacy room did not mount shared Agent scene",
	)

	var loaded_mode := world_root.switch_location("parametric")
	await process_frame
	await process_frame
	_assert(loaded_mode == "parametric", "parametric switch failed")
	var room := world_root.get_node_or_null("LivingRoom")
	_assert(room != null, "generated LivingRoom missing")
	if room != null:
		_check_parametric_room(room)

	var fallback_mode := world_root.switch_location("unknown_mode")
	for _frame in range(3):
		await process_frame
	_assert(fallback_mode == "legacy", "invalid mode did not fall back")
	_assert(world_root.has_node("LivingRoom/Agent"), "legacy fallback cast missing")

	scene.free()
	await process_frame
	print("WORLD_LOCATION_LOADER_%s" % ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)


## [S4.1][C6.2] 检查生成房间模型覆盖、导航和三个角色宿主节点。
func _check_parametric_room(room: Node) -> void:
	var report: Dictionary = room.get("build_report")
	_assert(int(report.get("placements", 0)) == 15, "generated placement count")
	_assert(int(report.get("loaded", 0)) == 15, "generated model coverage")
	_assert(int(report.get("fallbacks", -1)) == 0, "generated fallback present")
	_assert(room.has_node("GeneratedRoom/Structure/NavigationRegion3D"), "generated nav missing")
	_assert(room.has_node("TV/PhysicsBody"), "generated public TV path missing")
	for node_name in ["Agent", "JueAgent", "LocalCharacterSpawner"]:
		_assert(room.has_node(node_name), "cast node missing: %s" % node_name)
	var expected_scenes := {
		"Agent": "res://scenes/characters/main_agent.tscn",
		"JueAgent": "res://scenes/characters/jue_agent.tscn",
		"LocalCharacterSpawner": "res://scenes/characters/local_character_spawner.tscn",
	}
	for node_name in expected_scenes:
		var cast_node := room.get_node(node_name)
		_assert(
			cast_node.scene_file_path == expected_scenes[node_name],
			"cast is not independently instanced: %s" % node_name,
		)
	_check_generated_collisions(room)
	_check_generated_state(room)


## [S3.3][S4.1] 验证所有生成物理角色都有碰撞，portable 刚体初始冻结。
func _check_generated_collisions(room: Node) -> void:
	var collision_count := 0
	for child in room.get_children():
		if not child is Node3D:
			continue
		var physics_role := String(child.get_meta("physics_role", "none"))
		if physics_role == "none":
			continue
		var body := child.get_node_or_null("PhysicsBody") as CollisionObject3D
		_assert(body != null, "generated physics body missing: %s" % child.name)
		if body == null:
			continue
		_assert(
			body.has_node("CollisionShape"),
			"generated collision shape missing: %s" % child.name,
		)
		if body is RigidBody3D:
			_assert((body as RigidBody3D).freeze, "generated rigid body not frozen")
		collision_count += 1
	_assert(collision_count == 14, "generated collision coverage mismatch")


## [S3.2][T2.2] 验证植物浇水与落地灯开关同时更新语义和视觉状态。
func _check_generated_state(room: Node) -> void:
	var semantic_world := root.get_node("SemanticWorld")
	var plant_body := room.get_node(
		"Plant/PhysicsBody"
	)
	var moisture_before := float(semantic_world.get_object("plant").properties.get("moisture", 0.0))
	var plant_result: Dictionary = plant_body.perform_interaction("water", "main_agent")
	var moisture_after := float(semantic_world.get_object("plant").properties.get("moisture", 0.0))
	_assert(bool(plant_result.get("success", false)), "generated plant water failed")
	_assert(moisture_after > moisture_before, "generated plant moisture did not change")

	var lamp_body := room.get_node(
		"StandingLamp/PhysicsBody"
	)
	var lamp_result: Dictionary = lamp_body.perform_interaction("turn_off", "main_agent")
	var lamp_light := room.get_node(
		"StandingLamp/GeneratedWarmLight"
	) as OmniLight3D
	_assert(bool(lamp_result.get("success", false)), "generated lamp turn_off failed")
	_assert(is_zero_approx(lamp_light.light_energy), "generated lamp light stayed on")


## [S2.1] 累积失败并保留全部诊断。
func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("WORLD_LOCATION_LOADER_FAIL: " + message)
