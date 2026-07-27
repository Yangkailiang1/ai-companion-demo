extends SceneTree

const TEST_SAVE_PATH := "/private/tmp/v06_save_plant_contract_test.json"
var failed := false


## [T4.5] Starts the asynchronous save-contract acceptance flow.
func _init() -> void:
	call_deferred("_run")


## [T4.3][T4.5] Composes world, Agent and semantic-object persistence checks.
func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var context := _build_context(scene)
	var baseline := await _establish_and_save(context)
	_mutate_runtime_state(context)
	await _load_and_verify(context, baseline)
	_verify_post_load_interaction(context)
	_remove_test_save()
	print("SAVE_PLANT_STATE_PASS schema=%d plant=%s" % [
		context.save_system.SCHEMA_VERSION,
		context.plant_state.get_state_name(),
	])
	scene.free()
	quit(1 if failed else 0)


## [T4.3] Resolves persistent services, semantic objects and scene actors.
func _build_context(scene: Node) -> Dictionary:
	return {
		"semantic_world": root.get_node("SemanticWorld"),
		"world_simulator": root.get_node("WorldSimulator"),
		"save_system": root.get_node("SaveSystem"),
		"psyche_system": root.get_node("AgentPsycheSystem"),
		"bus": root.get_node("MessageBus"),
		"plant": scene.get_node("WorldRoot/LivingRoom/Plant"),
		"plant_state": scene.get_node("WorldRoot/LivingRoom/Plant/PlantState"),
		"main_agent": scene.get_node("WorldRoot/LivingRoom/Agent"),
		"jue_agent": scene.get_node("WorldRoot/LivingRoom/JueAgent"),
	}


## [T4.3] Establishes deterministic state and writes the contract snapshot.
func _establish_and_save(context: Dictionary) -> Dictionary:
	var plant_state: Node = context.plant_state
	plant_state.moisture = 8.0
	plant_state.health = 70.0
	plant_state._sync_state()
	_assert(plant_state.get_state_name() == "严重缺水", "plant must become severely dry")
	_assert("严重缺水" in context.semantic_world.generate_semantic_snapshot(), "semantic snapshot must expose plant state")
	context.world_simulator.game_time = 17.0
	context.world_simulator.day_number = 4
	context.main_agent.global_position = Vector3(-2.2, 0.0, 1.1)
	context.jue_agent.global_position = Vector3(1.8, 0.0, -1.2)
	context.bus.player_attention_requested.emit("main_agent", "谢谢你陪着我")
	await process_frame
	var save_error: Error = context.save_system.save_game(TEST_SAVE_PATH)
	_assert(save_error == OK, "save_game failed: error=%d detail=%s" % [save_error, context.save_system.last_error])
	return {
		"main_position": context.main_agent.global_position,
		"jue_position": context.jue_agent.global_position,
	}


## [T4.3] Replaces persisted values so restoration can be observed directly.
func _mutate_runtime_state(context: Dictionary) -> void:
	context.world_simulator.game_time = 2.0
	context.world_simulator.day_number = 1
	context.main_agent.global_position = Vector3.ZERO
	context.jue_agent.global_position = Vector3.ZERO
	context.psyche_system.import_save_state({
		"main_agent": {
			"mood": {"valence": -0.8, "arousal": 0.95},
			"attention": "temporary_test_target",
			"intention": "",
			"beliefs": {},
			"recent_activities": [],
			"private_thoughts": [],
		}
	})
	context.plant_state.perform_interaction("water", "main_agent")
	_assert(context.plant_state.moisture > 35.0, "water interaction must change moisture before reload")


## [T4.3] Reloads the snapshot and verifies every supported persistent subsystem.
func _load_and_verify(context: Dictionary, baseline: Dictionary) -> void:
	var load_error: Error = context.save_system.load_game(TEST_SAVE_PATH)
	_assert(load_error == OK, "load_game failed: error=%d detail=%s" % [load_error, context.save_system.last_error])
	await process_frame
	_assert(is_equal_approx(context.world_simulator.game_time, 17.0), "game time must restore")
	_assert(context.world_simulator.day_number == 4, "day number must restore")
	_assert(context.main_agent.global_position.distance_to(baseline.main_position) < 0.001, "main position must restore")
	_assert(context.jue_agent.global_position.distance_to(baseline.jue_position) < 0.001, "Jue position must restore")
	_assert(
		String(context.psyche_system.get_agent_state("main_agent").get("attention", "")) == "player",
		"main Agent psychology must restore"
	)
	_assert(context.plant_state.get_state_name() == "严重缺水", "plant structured state must restore")


## [T4.3] Confirms restored semantic objects remain interactable and synchronized.
func _verify_post_load_interaction(context: Dictionary) -> void:
	var interaction: Dictionary = context.plant.perform_interaction("water", "main_agent")
	_assert(bool(interaction.get("success", false)), "plant water affordance must succeed")
	_assert(context.plant_state.get_state_name() in ["状态良好", "需要浇水"], "watering must recover plant state")
	_assert(context.semantic_world.get_object("plant").properties.has("moisture"), "plant properties must remain semantic")


## [T4.3] Removes the isolated temporary contract snapshot.
func _remove_test_save() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEST_SAVE_PATH)
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(absolute_path)


## [T4.5] Records a stable failure while preserving test cleanup.
func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	failed = true
	push_error("SAVE_PLANT_STATE_FAIL: %s" % message)
