# Verifies: C5.3, C5.6, S2.5, S5, X1.2
# Covers: one offscreen resident activity, need/memory progression, arrival
# trace, rematerialization and journal save contract.

extends SceneTree

const TEST_SAVE_PATH := "/private/tmp/ai_companion_offscreen_life.json"

var _failed := false
var _life_trace_text := ""


## [C5.6] 延迟执行，等待 Autoload 与主场景进入树。
func _init() -> void:
	call_deferred("_run")


## [C5.3][C5.6] 执行离屏生活到重新进入房间的纵向验收。
func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var loader := scene.get_node("WorldRoot") as WorldLocationLoader
	loader.switch_location("parametric")
	await _settle()
	var simulator := loader.get_node("OffscreenLifeSimulator") as OffscreenLifeSimulator
	simulator.set_simulation_enabled(false)
	root.get_node("AutonomousBehaviorSystem").set_scheduler_enabled(false)
	_assert(
		loader.transfer_agent_via("jue_agent", "living_room", "to_bedroom"),
		"Jue did not leave living room",
	)
	await _settle_long()
	_assert(not loader.get_active_location().has_node("JueAgent"), "offscreen Jue still materialized")
	var needs: AffordanceTypes.NeedsState = (
		root.get_node("WorldSimulator").get_needs_for_agent("jue_agent")
	)
	needs.energy = 10.0
	var events := simulator.simulate_now(false, 1, 12.0)
	_assert(events.size() == 1, "offscreen event count")
	_assert(needs.energy > 10.0, "offscreen rest did not restore energy")
	_assert(
		simulator.get_location_journal("bedroom").size() == 1,
		"bedroom journal missing",
	)
	_assert(_memory_contains("jue_agent", "玩家不在场时"), "offscreen memory missing")
	var bus := root.get_node("MessageBus")
	bus.ui_add_chat_entry.connect(_capture_life_trace)
	_assert(loader.travel_via("to_bedroom"), "player could not enter bedroom")
	await _settle_long()
	_assert(loader.get_active_location().has_node("JueAgent"), "Jue did not rematerialize")
	_assert("诀" in _life_trace_text, "arrival life trace not shown")
	_verify_save_contract(simulator)
	var modes := root.get_node("ExperienceModeManager")
	modes.enter_performance_mode()
	_assert(
		simulator.simulate_now(true, 1, 18.0).is_empty(),
		"offscreen life leaked into performance mode",
	)
	scene.free()
	DirAccess.remove_absolute(TEST_SAVE_PATH)
	await process_frame
	if not _failed:
		print("OFFSCREEN_LIFE_SIMULATION_PASS activity=rest memory=true arrival_trace=true")
	quit(1 if _failed else 0)


## [C5.6] 捕获折叠聊天中的生活记录。
func _capture_life_trace(speaker: String, text: String, _is_player: bool) -> void:
	if speaker == "life_trace":
		_life_trace_text = text


## [C5.6] 检查指定角色的独立情景记忆。
func _memory_contains(agent_id: String, needle: String) -> bool:
	var memory := root.get_node("MemorySystem")
	for episode in memory.agent_memories.get(agent_id, {}).get("episodes", []):
		if needle in String(episode.get("content", "")):
			return true
	return false


## [C5.6][X1.2] 日志必须进入 v2 存档，且可独立恢复。
func _verify_save_contract(simulator: OffscreenLifeSimulator) -> void:
	var save_system := root.get_node("SaveSystem")
	_assert(save_system.save_game(TEST_SAVE_PATH) == OK, "offscreen save failed")
	var file := FileAccess.open(TEST_SAVE_PATH, FileAccess.READ)
	var snapshot = JSON.parse_string(file.get_as_text()) if file != null else {}
	_assert(
		snapshot is Dictionary
		and snapshot.get("offscreen_life", {}).get("journal_by_location", {}).has("bedroom"),
		"offscreen journal absent from save",
	)
	var exported := simulator.export_save_state()
	simulator.import_save_state({"journal_by_location": {}})
	_assert(simulator.get_location_journal("bedroom").is_empty(), "journal clear fixture")
	simulator.import_save_state(exported)
	_assert(not simulator.get_location_journal("bedroom").is_empty(), "journal restore failed")


## [C5.6] 等待常驻房间构建。
func _settle() -> void:
	for _frame in range(6):
		await physics_frame
		await process_frame


## [C5.6] 等待角色退役/重新实体化的安全宽限期。
func _settle_long() -> void:
	await create_timer(1.25).timeout
	await _settle()


## [C5.6] 累积失败诊断。
func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("OFFSCREEN_LIFE_SIMULATION_FAIL: " + message)
