# Verifies: C4.4, C9.5b, S3.3
# Covers: plan -> navigate -> carry can -> water plant -> release can

extends SceneTree

var failed := false
var completed := false
var failure_reason := ""
var saw_watering_cue := false
var saw_pour_start := false
var saw_pour_finish := false


## [C4.4][C9.5b] Starts the asynchronous embodied-watering acceptance flow.
func _init() -> void:
	call_deferred("_run")


## [C4.4][C9.5b][S3.3] Runs the real primitive queue and checks world effects.
func _run() -> void:
	OS.set_environment("AI_GAMES_WORLD_MODE", "parametric")
	root.get_node("AutonomousBehaviorSystem").set_scheduler_enabled(false)
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	for _frame in range(5):
		await physics_frame
	var room := scene.get_node("WorldRoot/LivingRoom")
	var agent := room.get_node("Agent") as Node3D
	await _wait_for_navigation(agent)
	var can_body := room.get_node("WateringCan/PhysicsBody") as RigidBody3D
	var can_home := can_body.get_parent()
	var presentation := can_body.find_child(
		"StylizedWateringCan", true, false
	)
	_assert(presentation != null, "watering presentation missing")
	if presentation != null:
		presentation.tool_use_started.connect(
			func(verb: String): saw_pour_start = verb == "water"
		)
		presentation.tool_use_finished.connect(
			func(verb: String): saw_pour_finish = verb == "water"
		)
	var plant = root.get_node("SemanticWorld").get_object("plant")
	plant.properties["moisture"] = 10.0
	var moisture_before := float(plant.properties.get("moisture", 0.0))
	var planner := GOAPPlanner.new()
	root.add_child(planner)
	await process_frame
	var actions := planner.plan("water_plant")
	_verify_plan(actions)
	var executor := ActionExecutor.new()
	root.add_child(executor)
	executor.queue_completed.connect(func(_agent_id: String): completed = true)
	executor.queue_failed.connect(func(_agent_id: String, reason: String, _context: Dictionary):
		failure_reason = reason
	)
	root.get_node("MessageBus").performance_cue.connect(
		func(gesture: String, context: Dictionary):
			if gesture == "nod" and String(context.get("interaction", "")) == "water":
				saw_watering_cue = true
	)
	executor.start_queue(agent, actions)
	var started_at := Time.get_ticks_msec()
	while not completed and failure_reason.is_empty() and Time.get_ticks_msec() - started_at < 14000:
		await physics_frame
	_assert(completed, "queue did not complete: " + failure_reason)
	_assert(can_body.get_parent() == can_home, "watering can was not released")
	_assert(can_body.freeze == false, "released watering can did not resume physics")
	_assert(float(plant.properties.get("moisture", 0.0)) > moisture_before,
		"watering did not increase plant moisture")
	_assert(saw_watering_cue, "watering performance cue was not emitted")
	_assert(saw_pour_start and saw_pour_finish, "watering presentation did not complete")
	_assert(
		presentation == null or not bool(presentation.get("is_pouring")),
		"watering presentation stayed active",
	)
	print("EMBODIED_WATERING_%s moisture=%.1f actions=%d" % [
		"FAIL" if failed else "PASS",
		float(plant.properties.get("moisture", 0.0)),
		actions.size(),
	])
	scene.free()
	quit(1 if failed else 0)


## [C4.4][C9.5b] Verifies the portable-tool primitive ordering.
func _verify_plan(actions: Array) -> void:
	_assert(actions.size() == 5, "watering plan must contain five primitives")
	if actions.size() != 5:
		return
	var types := [
		AffordanceTypes.Primitive.NAVIGATE,
		AffordanceTypes.Primitive.PICK_UP,
		AffordanceTypes.Primitive.NAVIGATE,
		AffordanceTypes.Primitive.INTERACT,
		AffordanceTypes.Primitive.PUT_DOWN,
	]
	for index in range(types.size()):
		_assert(actions[index].type == types[index], "unexpected primitive at %d" % index)
	_assert(String(actions[1].params.get("object", "")) == "watering_can",
		"plan does not pick up watering can")
	_assert(String(actions[3].params.get("verb", "")) == "water",
		"plan does not water plant")


## [C4.1] Waits for the active room NavigationServer map.
func _wait_for_navigation(agent: Node3D) -> void:
	var nav := agent.get_node("NavigationAgent3D") as NavigationAgent3D
	for _frame in range(90):
		if NavigationServer3D.map_get_iteration_id(nav.get_navigation_map()) >= 2:
			return
		await physics_frame
	_assert(false, "navigation map did not synchronize")


## [T4.2] Records a stable acceptance failure.
func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	failed = true
	push_error("EMBODIED_WATERING_FAIL: " + message)
