# Verifies: S2.2, S2.5, C5.3, X1.2
# Covers: per-agent residency -> AI traverse without player travel -> current
# room reconciliation -> destination materialization -> save/load restore.

extends SceneTree

const SAVE_PATH := "/private/tmp/ai_companion_agent_residency_v2.json"

var _failed := false


func _init() -> void:
	call_deferred("_run")


## [C5.3][S2.2][X1.2] 验证 AI 与玩家旅行解耦及居民位置持久化。
func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	root.get_node("AutonomousBehaviorSystem").set_scheduler_enabled(false)
	var loader := scene.get_node("WorldRoot") as WorldLocationLoader
	var residency := loader.get_residency_registry()
	_assert(residency != null, "residency registry missing")
	residency.import_save_state({"agent_locations": {
		"main_agent": "living_room",
		"jue_agent": "living_room",
		"castorice_agent": "living_room",
		"cartethyia_agent": "living_room",
		"xiangliyao_agent": "living_room",
	}})
	_assert(loader.travel_to("living_room"), "living room load failed")
	await _settle()
	var room := loader.get_active_location()
	_assert(room.has_node("JueAgent"), "Jue not materialized at home")
	var player_before: Vector3 = (loader.get_node("PlayerBody") as Node3D).global_position
	var portal := room.get_node_or_null("Portal_door_to_bedroom")
	_assert(portal != null, "bedroom portal missing")
	var result: Dictionary = portal.perform_interaction("traverse", "jue_agent")
	_assert(bool(result.get("success", false)), "AI traverse rejected")
	_assert(loader.current_location_id == "living_room", "AI traverse moved player room")
	_assert(
		loader.get_node("PlayerBody").global_position.distance_to(player_before) < 0.01,
		"AI traverse moved PlayerBody",
	)
	_assert(
		residency.get_agent_location("jue_agent") == "bedroom",
		"Jue logical location not updated",
	)
	await create_timer(1.25).timeout
	await process_frame
	_assert(not loader.get_active_location().has_node("JueAgent"), "departed Jue still visible")
	_assert(root.get_node("SaveSystem").save_game(SAVE_PATH) == OK, "residency save failed")
	_assert(residency.move_agent("jue_agent", "living_room"), "fixture mutation failed")
	loader.reconcile_active_cast()
	await process_frame
	_assert(loader.get_active_location().has_node("JueAgent"), "Jue did not return for fixture")
	_assert(root.get_node("SaveSystem").load_game(SAVE_PATH) == OK, "residency load failed")
	await process_frame
	_assert(
		residency.get_agent_location("jue_agent") == "bedroom",
		"saved residency not restored",
	)
	_assert(not loader.get_active_location().has_node("JueAgent"), "load did not reconcile cast")
	_assert(loader.travel_via("to_bedroom"), "player bedroom travel failed")
	await _settle()
	_assert(loader.get_active_location().has_node("JueAgent"), "Jue absent at destination")
	_assert(loader.get_active_location().has_node("Agent"), "companion absent at destination")
	_assert(
		not loader.get_active_location().has_node("LocalCharacterSpawner"),
		"living-room locals followed player",
	)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	scene.free()
	await process_frame
	if not _failed:
		print("AGENT_RESIDENCY_PASS ai_traverse=true player_static=true save=true")
	quit(1 if _failed else 0)


func _settle() -> void:
	for _frame in range(7):
		await physics_frame
		await process_frame


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("AGENT_RESIDENCY_FAIL: " + message)
