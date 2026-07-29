# Roadmap: C4.4, C4.5, T1.2
# Responsibility: 顺序执行白名单 Primitive Action，并在首个失败处终止队列；
#   不做认知决策，也不直接实现物体状态机。
# Collaborators: ActionExecutionResult, ActionObjectInteractor, AgentBase
# Tests: scripts/debug/action_failure_contract_check.gd
class_name ActionExecutor
extends Node

const ResultClass = preload("res://scripts/core/action_execution_result.gd")
const ObjectInteractorClass = preload("res://scripts/core/action_object_interactor.gd")

var action_queue: Array = []
var current_action_index: int = 0
var current_action: AffordanceTypes.PrimitiveAction = null

# 引用的 Agent 节点
var agent_node: Node3D = null

# 执行状态
var is_executing: bool = false
var _cancelled: bool = false
var _object_interactor = ObjectInteractorClass.new()
signal queue_completed(agent_id: String)
signal queue_failed(agent_id: String, reason: String, context: Dictionary)
signal action_completed(action: AffordanceTypes.PrimitiveAction)


## [C4.5][T1.2] 初始化一条动作队列；空队列按成功完成处理。
func start_queue(agent: Node3D, actions: Array) -> void:
	agent_node = agent
	action_queue = actions
	current_action_index = 0
	is_executing = true
	_cancelled = false
	_execute_next()


## [C4.5] 取消队列和移动；取消不发出成功事件。
func cancel() -> void:
	_cancelled = true
	is_executing = false
	action_queue.clear()
	if is_instance_valid(agent_node) and agent_node.has_method("cancel_movement"):
		agent_node.cancel_movement("action_cancelled")


## [C4.5] 执行下一项；队列耗尽时仅发出成功完成事件。
func _execute_next() -> void:
	if _cancelled:
		return
	if current_action_index >= action_queue.size():
		is_executing = false
		queue_completed.emit(_agent_id())
		return

	current_action = action_queue[current_action_index]
	_execute_action(current_action)


## [C4.4][C4.5] 分派白名单 Primitive；未知类型稳定失败。
func _execute_action(action: AffordanceTypes.PrimitiveAction) -> void:
	match action.type:
		AffordanceTypes.Primitive.NAVIGATE:
			_navigate(action.params)
		AffordanceTypes.Primitive.NAVIGATE_POSITION:
			_navigate_position(action.params)
		AffordanceTypes.Primitive.PATROL:
			_patrol(action.params)
		AffordanceTypes.Primitive.WANDER:
			_wander(action.params)
		AffordanceTypes.Primitive.INTERACT:
			_interact(action.params)
		AffordanceTypes.Primitive.SPEAK:
			_speak(action.params)
		AffordanceTypes.Primitive.IDLE:
			_idle(action.params)
		AffordanceTypes.Primitive.LOOK_AT:
			_look_at(action.params)
		AffordanceTypes.Primitive.PICK_UP:
			_pick_up(action.params)
		AffordanceTypes.Primitive.PUT_DOWN:
			_put_down(action.params)
		AffordanceTypes.Primitive.SIT:
			_sit(action.params)
		_:
			_fail_queue("unknown_primitive", {})


## [C4.2][C4.5] 导航到语义物体交互点；未知目标立即失败。
func _navigate(params: Dictionary) -> void:
	var target_id: String = params.get("target", "")
	if target_id.is_empty():
		_fail_queue("target_missing", {"target": target_id})
		return

	var semantic_world := _autoload("SemanticWorld")
	var obj = semantic_world.get_object(target_id) if semantic_world != null else null
	if not obj:
		_fail_queue("target_not_found", {"target": target_id})
		return

	_finish_result(await _travel_to(obj.interaction_point), {"target": target_id})


## [C4.1][C4.5] 导航到已校验 waypoint/坐标；不安全坐标失败。
func _navigate_position(params: Dictionary) -> void:
	var navigation := RoomNavigation.new()
	var target := Vector3.ZERO
	var waypoint_name := String(params.get("waypoint", ""))
	if not waypoint_name.is_empty() and navigation.has_waypoint(waypoint_name):
		target = navigation.get_waypoint(waypoint_name)
	else:
		target = _to_vec3(params.get("position", Vector3.ZERO))
	if not navigation.is_safe_position(target):
		_fail_queue("unsafe_target", {"target_position": target})
		return
	_finish_result(await _travel_to(target), {"target_position": target})


## [C4.1][C4.5] 顺序执行巡逻路径；首个失败段停止整条队列。
func _patrol(params: Dictionary) -> void:
	var navigation := RoomNavigation.new()
	var route_name := String(params.get("route", "room_perimeter"))
	var laps := clampi(int(params.get("laps", 1)), 1, 3)
	var route := navigation.get_route(route_name, laps)
	if route.size() < 2:
		_fail_queue("route_missing", {"route": route_name})
		return
	if agent_node.has_method("begin_locomotion_sequence"):
		agent_node.begin_locomotion_sequence()
	for target in route:
		if _cancelled:
			return
		var result := await _travel_to(target)
		if not ResultClass.is_success(result):
			if is_instance_valid(agent_node) and agent_node.has_method("end_locomotion_sequence"):
				agent_node.end_locomotion_sequence()
			_finish_result(result, {"route": route_name, "target_position": target})
			return
	if is_instance_valid(agent_node) and agent_node.has_method("end_locomotion_sequence"):
		agent_node.end_locomotion_sequence()
	_on_action_finished()


## [C4.1][C4.5] 导航到确定性漫游点并传播到达失败。
func _wander(params: Dictionary) -> void:
	var navigation := RoomNavigation.new()
	var point_index := int(params.get("point_index", -1))
	var from_position := agent_node.global_position if is_instance_valid(agent_node) else Vector3.ZERO
	var target := navigation.get_wander_point_away(from_position, 1.0, point_index)
	_finish_result(await _travel_to(target), {"target_position": target})


## [C4.1][C4.5] 等待 AgentBase movement_finished，并返回稳定原因。
func _travel_to(target: Vector3) -> Dictionary:
	if _cancelled or not is_instance_valid(agent_node):
		return ResultClass.failure("cancelled")
	if not agent_node.has_method("move_to_position"):
		return ResultClass.failure("movement_capability_missing")
	agent_node.move_to_position(target)
	if agent_node.has_signal("movement_finished"):
		var movement_result: Array = await agent_node.movement_finished
		if _cancelled:
			return ResultClass.failure("cancelled")
		var success := bool(movement_result[0]) if movement_result.size() > 0 else false
		var reason := String(movement_result[1]) if movement_result.size() > 1 else "unreachable"
		return ResultClass.success({"target_position": target}) if success else ResultClass.failure(
			reason, {"target_position": target}
		)
	while not _cancelled and is_instance_valid(agent_node) and agent_node.is_moving:
		await get_tree().process_frame
	if _cancelled or not is_instance_valid(agent_node):
		return ResultClass.failure("cancelled")
	if agent_node.global_position.distance_to(target) <= 0.75:
		return ResultClass.success({"target_position": target})
	return ResultClass.failure("unreachable", {"target_position": target})


## [C4.4][C4.5] 执行通用物体交互；只有成功结果可继续队列。
func _interact(params: Dictionary) -> void:
	var obj_id: String = params.get("object", "")
	var verb: String = params.get("verb", "")
	if not String(params.get("held_tool", "")).is_empty():
		await _play_held_tool(params, obj_id)
		if _cancelled:
			return
	var result := _object_interactor.perform(obj_id, verb, _agent_id())
	if not ResultClass.is_success(result):
		_finish_result(result)
		return
	if verb == "water":
		var message_bus := _autoload("MessageBus")
		if message_bus != null:
			message_bus.performance_cue.emit("nod", {
				"source": "executor",
				"agent_id": _agent_id(),
				"interaction": "water",
				"held_tool": String(params.get("held_tool", "")),
			})
	await get_tree().create_timer(1.0).timeout
	_on_action_finished()


## [C4.4][C9.5b] 让当前持有工具自行播放使用表现；缺失表现组件时保持兼容。
func _play_held_tool(params: Dictionary, target_id: String) -> void:
	var semantic_world := _autoload("SemanticWorld")
	if semantic_world == null:
		return
	var held_tool = semantic_world.get_object(
		String(params.get("held_tool", ""))
	)
	var target = semantic_world.get_object(target_id)
	if held_tool == null or not is_instance_valid(held_tool.godot_node):
		return
	if not held_tool.godot_node.has_method("play_tool_use"):
		return
	var target_position: Vector3 = (
		target.position if target != null else Vector3.ZERO
	)
	await held_tool.godot_node.play_tool_use(
		String(params.get("verb", "")), target_position
	)


func _speak(params: Dictionary) -> void:
	var text: String = params.get("text", "")
	var tone: String = params.get("tone", "neutral")
	var message_bus := _autoload("MessageBus")
	if message_bus == null:
		_fail_queue("message_bus_missing", {})
		return
	if not text.is_empty():
		message_bus.agent_show_bubble.emit(_agent_id(), text, tone, 4.0)
	message_bus.performance_cue.emit("talk", {"source": "executor", "agent_id": _agent_id()})
	# speak 不阻塞，立即继续
	_on_action_finished()


func _idle(params: Dictionary) -> void:
	var duration: float = params.get("duration", 1.0)
	await get_tree().create_timer(duration).timeout
	_on_action_finished()


func _look_at(params: Dictionary) -> void:
	# 转向目标
	var target_id: String = params.get("target", "")
	if not target_id.is_empty() and agent_node and agent_node.has_method("look_at_target"):
		agent_node.look_at_target(target_id)
	await get_tree().create_timer(0.5).timeout
	_on_action_finished()


## [C4.4][C4.5] 执行拿取；失败时不播放等待或继续后续动作。
func _pick_up(params: Dictionary) -> void:
	var result := _object_interactor.perform(String(params.get("object", "")), "pick_up", _agent_id())
	if not ResultClass.is_success(result):
		_finish_result(result)
		return
	await get_tree().create_timer(0.5).timeout
	_on_action_finished()


## [C4.4][C4.5] 执行放下并传播持有者/预订失败。
func _put_down(params: Dictionary) -> void:
	var result := _object_interactor.perform(String(params.get("object", "")), "put_down", _agent_id())
	if not ResultClass.is_success(result):
		_finish_result(result)
		return
	await get_tree().create_timer(0.5).timeout
	_on_action_finished()


## [C4.4][C4.5] 执行座位交互成功后才播放 sit 表现。
func _sit(params: Dictionary) -> void:
	var object_id := String(params.get("object", ""))
	var result := _object_interactor.perform(object_id, "sit", _agent_id())
	if not ResultClass.is_success(result):
		_finish_result(result)
		return
	var message_bus := _autoload("MessageBus")
	if message_bus != null:
		message_bus.performance_cue.emit("sit", {"source": "executor", "agent_id": _agent_id()})
	await get_tree().create_timer(0.8).timeout
	_on_action_finished()


# === 内部 ===

## [C4.5][T1.2] 标记当前 primitive 成功并调度下一项。
func _on_action_finished() -> void:
	if _cancelled:
		return
	action_completed.emit(current_action)
	current_action_index += 1
	call_deferred("_execute_next")


## [C4.5][T1.2] 合并调用方上下文后，将结果路由到成功或失败出口。
func _finish_result(result: Dictionary, extra_context: Dictionary = {}) -> void:
	if _cancelled:
		return
	if ResultClass.is_success(result):
		_on_action_finished()
		return
	var context: Dictionary = result.get("context", {}).duplicate(true)
	context.merge(extra_context, true)
	_fail_queue(String(result.get("reason", "action_failed")), context)


## [C4.5][T1.2] 首次失败停止剩余队列，并且只发出一次失败事件。
func _fail_queue(reason: String, context: Dictionary) -> void:
	if _cancelled:
		return
	is_executing = false
	_cancelled = true
	action_queue.clear()
	context = context.duplicate(true)
	context["action_index"] = current_action_index
	if current_action != null:
		context["primitive"] = int(current_action.type)
	if is_instance_valid(agent_node) and agent_node.has_method("cancel_movement"):
		agent_node.cancel_movement("action_failed")
	queue_failed.emit(_agent_id(), reason, context)


func _to_vec3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	if value is Dictionary:
		return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))
	return Vector3.ZERO


func _agent_id() -> String:
	if is_instance_valid(agent_node) and agent_node.get("agent_name") != null:
		return String(agent_node.get("agent_name"))
	return ""


## [T4.2] Resolves runtime services without requiring autoload identifiers
## while standalone headless contracts compile this executor.
func _autoload(singleton_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(singleton_name) if tree != null else null
