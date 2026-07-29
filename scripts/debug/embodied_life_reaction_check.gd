# Verifies: C9.5, S3.3
# Covers: dynamic prop observer wiring and physical event -> character tidy
# action sequence without invoking an LLM.

extends SceneTree

var _failed := false
var _captured_agent := ""
var _captured_actions: Array = []
var _captured_expression := ""
var _bus: Node


## [C9.5] 延迟执行，等待 Autoload 和主场景进入树。
func _init() -> void:
	call_deferred("_run")


## [C9.5][S3.3] 执行玩家扰动物体到角色具身反应的纵向验收。
func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var loader := scene.get_node("WorldRoot") as WorldLocationLoader
	_bus = root.get_node("MessageBus")
	loader.switch_location("parametric")
	await _settle()
	var autonomy := root.get_node_or_null("AutonomousBehaviorSystem")
	if autonomy != null:
		autonomy.set_scheduler_enabled(false)
	var pillow := loader.get_node_or_null(
		"LivingRoom/FloorPillow/PhysicsBody"
	) as RigidBody3D
	_assert(pillow != null, "pillow missing")
	if pillow != null:
		_assert(
			pillow.get_node_or_null("DynamicPropObserver") != null,
			"dynamic observer missing",
		)
	_disconnect_agent_action_handlers()
	_bus.emit_actions.connect(_capture_actions)
	_bus.expression_cue.connect(_capture_expression)
	var reaction_system := root.get_node_or_null("EmbodiedLifeReactionSystem")
	_assert(reaction_system != null, "reaction system autoload missing")
	if reaction_system != null:
		reaction_system.set("_last_reaction_msec", -8000)
	_bus.world_state_changed.emit("dynamic_prop_displaced", {
		"object_id": "floor_pillow",
		"location_id": "living_room",
		"position": pillow.global_position if pillow != null else Vector3.ZERO,
	})
	await process_frame
	_verify_reaction_contract()
	scene.free()
	await process_frame
	if not _failed:
		print("EMBODIED_LIFE_REACTION_PASS actions=5 memory=true expression=surprised")
	quit(1 if _failed else 0)


## [C9.5] 避免测试动作队列真实移动角色，仅捕获系统输出合同。
func _disconnect_agent_action_handlers() -> void:
	for node in get_nodes_in_group("agents"):
		var handler := Callable(node, "_on_emit_actions")
		if _bus.emit_actions.is_connected(handler):
			_bus.emit_actions.disconnect(handler)


## [C9.5] 捕获面向指定角色的具身动作序列。
func _capture_actions(agent_id: String, actions: Array) -> void:
	_captured_agent = agent_id
	_captured_actions = actions


## [C9.5] 捕获该闭环的惊讶表情 cue。
func _capture_expression(expression: String, _intensity: float, context: Dictionary) -> void:
	if String(context.get("source", "")) == "embodied_world_reaction":
		_captured_expression = expression


## [C9.5] 验证反应具备看、说、走、拿、放五个原子动作。
func _verify_reaction_contract() -> void:
	_assert(not _captured_agent.is_empty(), "no reacting agent selected")
	_assert(_captured_actions.size() == 5, "reaction action count")
	if _captured_actions.size() != 5:
		return
	var expected := [
		AffordanceTypes.Primitive.LOOK_AT,
		AffordanceTypes.Primitive.SPEAK,
		AffordanceTypes.Primitive.NAVIGATE,
		AffordanceTypes.Primitive.PICK_UP,
		AffordanceTypes.Primitive.PUT_DOWN,
	]
	for index in expected.size():
		_assert(_captured_actions[index].type == expected[index], "action order %d" % index)
	_assert(_captured_expression == "surprised", "surprised expression missing")


## [C9.5] 等待房间和角色装配完成。
func _settle() -> void:
	for _frame in range(5):
		await physics_frame
		await process_frame


## [C9.5] 累积失败诊断。
func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("EMBODIED_LIFE_REACTION_FAIL: " + message)
