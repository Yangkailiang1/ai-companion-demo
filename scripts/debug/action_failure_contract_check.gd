# Verifies: C4.5, C9.3, T1.2
# Covers: interaction failure -> queue stop -> no effects/success -> reservation release;
# success queue remains compatible; autonomous activity resources release on failure.

extends SceneTree

var _failed := false
var _queue_failures := 0
var _queue_completions := 0
var _later_speech_seen := false


## [C4.5][T4.5] 延迟运行，使 Autoload 和场景树先完成初始化。
func _init() -> void:
	call_deferred("_run")


## [C4.5][C9.3] 组合验证失败、成功和自主资源释放三条合同。
func _run() -> void:
	root.get_node("ExperienceModeManager").enter_performance_mode()
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var room := scene.get_node("WorldRoot/LivingRoom")
	_connect_capture()
	await _verify_failed_pickup_stops_queue(room)
	await _verify_nearby_success_still_completes(room)
	_verify_autonomous_resources_release()
	if not _failed:
		print("ACTION_FAILURE_CONTRACT_PASS failures=%d completions=%d" % [
			_queue_failures, _queue_completions,
		])
	root.get_node("AutonomousBehaviorSystem").set_scheduler_enabled(false)
	scene.free()
	await process_frame
	quit(1 if _failed else 0)


## [C4.5] 捕获全局队列结果和不应执行的后续对白。
func _connect_capture() -> void:
	var bus := root.get_node("MessageBus")
	bus.action_queue_failed.connect(func(agent_id: String, _reason: String, _context: Dictionary):
		if agent_id == "main_agent":
			_queue_failures += 1
	)
	bus.action_queue_completed.connect(func(agent_id: String):
		if agent_id == "main_agent":
			_queue_completions += 1
	)
	bus.agent_show_bubble.connect(func(agent_id: String, text: String, _emotion: String, _duration: float):
		if agent_id == "main_agent" and text == "SHOULD_NOT_RUN":
			_later_speech_seen = true
	)


## [C4.5][S3.3] 远距离拿取必须失败一次，后续动作和成功效果均不得发生。
func _verify_failed_pickup_stops_queue(room: Node) -> void:
	var agent := room.get_node("Agent") as CharacterBody3D
	var book := room.get_node("Book")
	agent.global_position = Vector3(-3.0, 0.0, 2.8)
	var original_parent := book.get_parent()
	var original_state := String(root.get_node("SemanticWorld").get_object("book").state)
	var needs = root.get_node("WorldSimulator").get_needs_for_agent("main_agent")
	needs.fun = 25.0
	var actions := [
		_action(AffordanceTypes.Primitive.PICK_UP, {"object": "book"}),
		_action(AffordanceTypes.Primitive.SPEAK, {"text": "SHOULD_NOT_RUN"}),
	]
	root.get_node("MessageBus").emit_actions.emit("main_agent", actions)
	await process_frame
	await process_frame
	_assert(_queue_failures == 1, "failed queue did not emit exactly once")
	_assert(_queue_completions == 0, "failed queue emitted success completion")
	_assert(not _later_speech_seen, "action after failure still executed")
	_assert(book.get_parent() == original_parent, "failed pickup changed object parent")
	_assert(book.get_reserved_by().is_empty(), "failed pickup leaked reservation")
	_assert(is_equal_approx(needs.fun, 25.0), "failed pickup applied need effects")
	_assert(
		String(root.get_node("SemanticWorld").get_object("book").state) == original_state,
		"failed pickup changed semantic state",
	)


## [C4.4][C4.5] 同一执行器在邻近位置仍可成功拿起并放下。
func _verify_nearby_success_still_completes(room: Node) -> void:
	var agent := room.get_node("Agent") as CharacterBody3D
	var book := room.get_node("Book")
	agent.global_position = book.global_position + Vector3(0.45, 0, 0.45)
	root.get_node("MessageBus").emit_actions.emit("main_agent", [
		_action(AffordanceTypes.Primitive.PICK_UP, {"object": "book"}),
		_action(AffordanceTypes.Primitive.PUT_DOWN, {"object": "book"}),
	])
	var started_at := Time.get_ticks_msec()
	while _queue_completions < 1 and Time.get_ticks_msec() - started_at < 3000:
		await process_frame
	_assert(_queue_completions == 1, "nearby success queue did not complete")
	_assert(_queue_failures == 1, "success queue emitted an extra failure")
	_assert(book.get_reserved_by().is_empty(), "put_down did not release reservation")
	_assert(book.get_parent() == room, "put_down did not restore room parent")


## [C4.5][C9.3] 自主队列失败必须释放活动和共享资源，不写成功诊断。
func _verify_autonomous_resources_release() -> void:
	var autonomy := root.get_node("AutonomousBehaviorSystem")
	autonomy.set_scheduler_enabled(false)
	autonomy._resource_owners["book"] = "main_agent"
	autonomy._active_activities["main_agent"] = {
		"activity_id": "read_book",
		"resources": ["book"],
		"started_at_msec": Time.get_ticks_msec(),
	}
	root.get_node("MessageBus").action_queue_failed.emit(
		"main_agent", "occupied", {"object_id": "book"}
	)
	_assert(not autonomy._resource_owners.has("book"), "activity resource was not released")
	_assert(not autonomy._active_activities.has("main_agent"), "failed activity stayed active")
	_assert(String(autonomy._diagnostics.get("status", "")) == "activity_failed",
		"failure was diagnosed as success")


## [T1.2] 构造测试用 PrimitiveAction。
func _action(type: AffordanceTypes.Primitive, params: Dictionary):
	return AffordanceTypes.PrimitiveAction.new(type, params)


## [T4.5] 记录稳定失败并允许清理完成。
func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("ACTION_FAILURE_CONTRACT_FAIL: " + message)
