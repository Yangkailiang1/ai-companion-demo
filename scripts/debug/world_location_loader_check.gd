# Verifies: S2.1, S4.1, C6.2
# Covers: legacy default -> parametric switch -> invalid-mode fallback.

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
	_assert(world_root.current_mode == "legacy", "main must default to legacy")
	_assert(world_root.has_node("LivingRoom/Sofa"), "legacy room path missing")

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
	for node_name in ["Agent", "JueAgent", "LocalCharacterSpawner"]:
		_assert(room.has_node(node_name), "cast node missing: %s" % node_name)
	_check_generated_state(room)


## [S3.2][T2.2] 验证植物浇水与落地灯开关同时更新语义和视觉状态。
func _check_generated_state(room: Node) -> void:
	var semantic_world := root.get_node("SemanticWorld")
	var plant_body := room.get_node(
		"GeneratedRoom/Placements/plant/PhysicsBody"
	)
	var moisture_before := float(semantic_world.get_object("plant").properties.get("moisture", 0.0))
	var plant_result: Dictionary = plant_body.perform_interaction("water", "main_agent")
	var moisture_after := float(semantic_world.get_object("plant").properties.get("moisture", 0.0))
	_assert(bool(plant_result.get("success", false)), "generated plant water failed")
	_assert(moisture_after > moisture_before, "generated plant moisture did not change")

	var lamp_body := room.get_node(
		"GeneratedRoom/Placements/standing_lamp/PhysicsBody"
	)
	var lamp_result: Dictionary = lamp_body.perform_interaction("turn_off", "main_agent")
	var lamp_light := room.get_node(
		"GeneratedRoom/Placements/standing_lamp/GeneratedWarmLight"
	) as OmniLight3D
	_assert(bool(lamp_result.get("success", false)), "generated lamp turn_off failed")
	_assert(is_zero_approx(lamp_light.light_energy), "generated lamp light stayed on")


## [S2.1] 累积失败并保留全部诊断。
func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("WORLD_LOCATION_LOADER_FAIL: " + message)
