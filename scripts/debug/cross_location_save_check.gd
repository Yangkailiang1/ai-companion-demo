# Verifies: X1.2, S2.2
# Covers: v2 save with location block, agent location_id, cross-location
# semantic deferred states, v1 migration, unknown-schema rejection, invalid
# location and malformed snapshot rejection.

extends SceneTree

const TEST_SAVE_PATH := "/private/tmp/ai_companion_cross_location_save_v2.json"
const TEST_V1_PATH := "/private/tmp/ai_companion_cross_location_save_v1.json"
const TEST_INVALID_LOC_PATH := "/private/tmp/ai_companion_cross_location_save_invalid_loc.json"
const TEST_UNKNOWN_SCHEMA_PATH := "/private/tmp/ai_companion_cross_location_save_bad_schema.json"
var _failed := false


## [X1.2] 延迟执行横切验收流程，等待主场景和 Autoload 完成初始化。
func _init() -> void:
	call_deferred("_run")


## [X1.2][S2.2] 编排跨地点持久化合同的分阶段验收。
func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var context := {
		"loader": scene.get_node("WorldRoot") as WorldLocationLoader,
		"semantic": root.get_node("SemanticWorld"),
		"save_sys": root.get_node("SaveSystem"),
	}
	root.get_node("AutonomousBehaviorSystem").set_scheduler_enabled(false)
	var saved := await _establish_v2_fixture(context)
	await _restore_v2_and_verify(context, saved)
	await _verify_deferred_and_one_shot(context, saved)
	await _verify_v1_migration(context.save_sys, context.loader)
	_verify_failure_protection(context.save_sys, context.loader)
	_remove_temporary_files()
	if not _failed:
		print("CROSS_LOCATION_SAVE_PASS schema=2 location=kitchen")
	scene.free()
	quit(1 if _failed else 0)


## [X1.2] 创建卧室/厨房对象状态和两个 Agent 坐标的 v2 存档样本。
func _establish_v2_fixture(context: Dictionary) -> Dictionary:
	var loader: WorldLocationLoader = context.loader
	var semantic: Node = context.semantic
	_assert(loader.switch_location("parametric") == "parametric", "living_room init")
	await _settle()
	_assert(loader.travel_via("to_bedroom"), "travel to bedroom")
	await _settle()
	semantic.update_object_state("bed", "被子堆成一团")
	_assert(loader.travel_via("to_living"), "travel to living")
	await _settle()
	_assert(loader.travel_via("to_kitchen"), "travel to kitchen")
	await _settle()
	semantic.update_object_state("kitchen_fridge", "嗡嗡运转")
	var room: Node = loader.get_active_location()
	var saved_main := Vector3(-2.1, 0.0, 0.7)
	var saved_jue := Vector3(1.8, 0.0, -0.6)
	(room.get_node("Agent") as Node3D).global_position = saved_main
	(room.get_node("JueAgent") as Node3D).global_position = saved_jue
	_assert(context.save_sys.save_game(TEST_SAVE_PATH) == OK, "save v2 failed: " + context.save_sys.last_error)
	return {"main": saved_main, "jue": saved_jue}


## [X1.2] 模拟重启后恢复活动房间、对象状态和两个 Agent 坐标。
func _restore_v2_and_verify(context: Dictionary, saved: Dictionary) -> void:
	var loader: WorldLocationLoader = context.loader
	var semantic: Node = context.semantic
	semantic.reset_for_testing()
	semantic.import_save_state({"future_probe": {"state": "valid", "properties": {}}})
	semantic.import_save_state({"future_probe": {"state": 7, "properties": []}})
	_assert(semantic.export_save_state().future_probe.state == "valid", "bad state erased valid pending")
	_assert(loader.travel_via("to_living"), "travel to living after reset")
	await _settle()
	var room: Node = loader.get_active_location()
	(room.get_node("Agent") as Node3D).global_position = Vector3(9.0, 0.0, 9.0)
	(room.get_node("JueAgent") as Node3D).global_position = Vector3(-9.0, 0.0, -9.0)
	_assert(context.save_sys.load_game(TEST_SAVE_PATH) == OK, "load v2 failed: " + context.save_sys.last_error)
	_assert(loader.current_mode == "parametric", "mode not parametric")
	_assert(loader.current_location_id == "kitchen", "not kitchen: " + loader.current_location_id)
	await _settle()
	room = loader.get_active_location()
	_assert(
		(room.get_node("Agent") as Node3D).global_position.distance_to(saved.main) < 0.02,
		"main pos not restored"
	)
	_assert(
		(room.get_node("JueAgent") as Node3D).global_position.distance_to(saved.jue) < 0.02,
		"jue pos not restored"
	)
	var fridge = semantic.get_object("kitchen_fridge")
	_assert(
		fridge != null and fridge.state == "嗡嗡运转",
		"fridge state not restored: %s" % (fridge.state if fridge else "null")
	)
	(room.get_node("Agent") as Node3D).global_position = Vector3(4.0, 0.0, 4.0)
	_assert(
		context.save_sys.load_game(TEST_SAVE_PATH) == OK,
		"same-room load failed: " + context.save_sys.last_error
	)
	await _settle()
	room = loader.get_active_location()
	_assert(
		(room.get_node("Agent") as Node3D).global_position.distance_to(saved.main) < 0.02,
		"same-room agent position not restored"
	)


## [X1.2] 验证未加载卧室的延迟对象恢复，以及 Agent 坐标仅应用一次。
func _verify_deferred_and_one_shot(context: Dictionary, saved: Dictionary) -> void:
	var loader: WorldLocationLoader = context.loader
	var semantic: Node = context.semantic
	_assert(loader.travel_via("to_living"), "kitchen → living (post-load)")
	await _settle()
	_assert(loader.travel_via("to_bedroom"), "living → bedroom (post-load)")
	await _settle()
	var bed = semantic.get_object("bed")
	_assert(bed != null, "bed not registered (X1.2 deferred)")
	_assert(bed.state == "被子堆成一团", "bed deferred state: %s" % bed.state)
	_assert(loader.travel_via("to_living"), "bedroom → living for one-shot check")
	await _settle()
	_assert(loader.travel_via("to_kitchen"), "living → kitchen for one-shot check")
	await _settle()
	var fresh_main := loader.get_active_location().get_node("Agent") as Node3D
	_assert(fresh_main.global_position.distance_to(saved.main) > 0.1, "saved position reapplied twice")


## [X1.2] 验证 v1 格式文件加载、内存迁移到 schema 2 且无无效跨房间传送。
func _verify_v1_migration(save_sys: Node, loader: WorldLocationLoader) -> void:
	_write_json(TEST_V1_PATH, {
		"schema_version": 1,
		"saved_at_unix": Time.get_unix_time_from_system(),
		"world": root.get_node("WorldSimulator").export_save_state(),
		"objects": {},
		"agents": {},
	})
	# After parametric setup, loading v1 should restore as legacy location
	_assert(loader.switch_location("parametric") == "parametric", "pre-v1-migrate travel")
	await _settle()
	_assert(save_sys.load_game(TEST_V1_PATH) == OK, "v1 load failed: " + save_sys.last_error)
	var snap: Dictionary = save_sys.get_snapshot()
	_assert(int(snap.get("schema_version", 0)) == 2, "v1 migration schema is %s" % str(snap.get("schema_version")))
	_assert(loader.current_mode == "legacy", "v1 migration mode: " + loader.current_mode)
	# Agent should not teleport to invalid location; legacy living_room is fine
	var room := loader.get_active_location()
	if room != null:
		var agent := room.get_node_or_null("Agent") as Node3D
		var wrong_pos := Vector3(9.0, 0.0, 9.0)
		if agent != null:
			_assert(agent.global_position.distance_to(wrong_pos) > 1.0, "v1 migration wrong teleport")
	# Switch back to parametric for remaining tests
	_assert(loader.switch_location("parametric") == "parametric", "post-v1 parametric restore")
	await _settle()


## [X1.2] 验证未知 schema 和无效应地点失败时保护当前房间。
func _verify_failure_protection(save_sys: Node, loader: WorldLocationLoader) -> void:
	# Bad schema — record active room before load, verify unchanged after
	_write_json(TEST_UNKNOWN_SCHEMA_PATH, {"schema_version": 99, "saved_at_unix": 1, "agents": {}})
	var loc_before := loader.current_location_id
	var err: Error = save_sys.load_game(TEST_UNKNOWN_SCHEMA_PATH)
	_assert(err == ERR_FILE_UNRECOGNIZED, "bad schema not rejected: %d" % err)
	_assert(
		loader.current_location_id == loc_before,
		"bad schema replaced room from %s to %s" % [loc_before, loader.current_location_id]
	)

	# Invalid location (valid v2 schema but nonexistent location_id)
	_write_json(TEST_INVALID_LOC_PATH, {
		"schema_version": 2,
		"saved_at_unix": 1,
		"location": {"world_mode": "parametric", "location_id": "nonexistent_room_xyz"},
		"world": {}, "objects": {}, "agents": {},
	})
	loc_before = loader.current_location_id
	var err_loc: Error = save_sys.load_game(TEST_INVALID_LOC_PATH)
	_assert(err_loc != OK, "invalid location not rejected: %d" % err_loc)
	_assert(
		loader.current_location_id == loc_before,
		"invalid location replaced room from %s to %s" % [
			loc_before, loader.current_location_id
		]
	)

	_write_json(TEST_INVALID_LOC_PATH, {
		"schema_version": 2,
		"location": {"world_mode": "parametric", "location_id": "living_room"},
		"world": {}, "objects": {},
		"agents": {"main_agent": {"position": "bad", "rotation": [0, 0, 0], "location_id": "living_room"}},
	})
	_assert(save_sys.load_game(TEST_INVALID_LOC_PATH) == ERR_INVALID_DATA, "bad agent snapshot accepted")
	_assert(loader.current_location_id == loc_before, "bad agent snapshot replaced room")


## [X1.2] 原子写入 JSON 到磁盘（仅测试用）。
func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


## [X1.2] 等待构造、语义注册、导航同步和延迟 Agent 坐标恢复。
func _settle() -> void:
	for _frame in range(6):
		await physics_frame
		await process_frame


## [X1.2] 累积断言失败但继续执行以收集完整诊断。
func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("CROSS_LOCATION_SAVE_FAIL: " + message)


## [X1.2] 删除测试过程中创建的临时文件。
func _remove_temporary_files() -> void:
	for p in [TEST_SAVE_PATH, TEST_V1_PATH, TEST_INVALID_LOC_PATH, TEST_UNKNOWN_SCHEMA_PATH]:
		var abs := ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(abs)
