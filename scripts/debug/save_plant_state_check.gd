extends SceneTree

const TEST_SAVE_PATH := "/private/tmp/v06_save_plant_contract_test.json"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var semantic_world := root.get_node("SemanticWorld")
	var world_simulator := root.get_node("WorldSimulator")
	var save_system := root.get_node("SaveSystem")
	var psyche_system := root.get_node("AgentPsycheSystem")
	var bus := root.get_node("MessageBus")
	var plant := scene.get_node("WorldRoot/LivingRoom/Plant")
	var plant_state := plant.get_node("PlantState")
	var main_agent: Node3D = scene.get_node("WorldRoot/LivingRoom/Agent")
	var jue_agent: Node3D = scene.get_node("WorldRoot/LivingRoom/JueAgent")

	plant_state.advance_hours(5)
	_assert(plant_state.get_state_name() == "严重缺水", "plant must become severely dry")
	_assert("严重缺水" in semantic_world.generate_semantic_snapshot(), "semantic snapshot must expose plant state")

	world_simulator.game_time = 17.0
	world_simulator.day_number = 4
	main_agent.global_position = Vector3(-2.2, 0.0, 1.1)
	jue_agent.global_position = Vector3(1.8, 0.0, -1.2)
	bus.player_attention_requested.emit("main_agent", "谢谢你陪着我")
	await process_frame
	var saved_main_position := main_agent.global_position
	var saved_jue_position := jue_agent.global_position
	var save_error: Error = save_system.save_game(TEST_SAVE_PATH)
	_assert(save_error == OK, "save_game must succeed: error=%d detail=%s" % [save_error, save_system.last_error])

	world_simulator.game_time = 2.0
	world_simulator.day_number = 1
	main_agent.global_position = Vector3.ZERO
	jue_agent.global_position = Vector3.ZERO
	psyche_system.import_save_state({
		"main_agent": {
			"mood": {"valence": -0.8, "arousal": 0.95},
			"attention": "temporary_test_target",
			"intention": "",
			"beliefs": {},
			"recent_activities": [],
			"private_thoughts": [],
		}
	})
	plant_state.perform_interaction("water", "main_agent")
	_assert(plant_state.moisture > 35.0, "water interaction must change moisture before reload")

	var load_error: Error = save_system.load_game(TEST_SAVE_PATH)
	_assert(load_error == OK, "load_game must succeed: error=%d detail=%s" % [load_error, save_system.last_error])
	await process_frame
	_assert(is_equal_approx(world_simulator.game_time, 17.0), "game time must restore")
	_assert(world_simulator.day_number == 4, "day number must restore")
	_assert(main_agent.global_position.distance_to(saved_main_position) < 0.001, "main agent position must restore")
	_assert(jue_agent.global_position.distance_to(saved_jue_position) < 0.001, "Jue position must restore")
	_assert(
		String(psyche_system.get_agent_state("main_agent").get("attention", "")) == "player",
		"main Agent psychology must restore"
	)
	_assert(plant_state.get_state_name() == "严重缺水", "plant structured state must restore")

	var interaction: Dictionary = plant.perform_interaction("water", "main_agent")
	_assert(bool(interaction.get("success", false)), "plant water affordance must succeed")
	_assert(plant_state.get_state_name() in ["状态良好", "需要浇水"], "watering must recover plant state")
	_assert(semantic_world.get_object("plant").properties.has("moisture"), "plant properties must remain semantic")

	var absolute_path := ProjectSettings.globalize_path(TEST_SAVE_PATH)
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(absolute_path)
	print("SAVE_PLANT_STATE_PASS schema=%d plant=%s" % [save_system.SCHEMA_VERSION, plant_state.get_state_name()])
	scene.free()
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("SAVE_PLANT_STATE_FAIL: %s" % message)
	quit(1)
	assert(condition, message)
