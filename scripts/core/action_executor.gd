# action_executor.gd — Primitive Action 执行器
# 设计文档 §五.1: 11 个 Primitive Actions 的逐帧执行
class_name ActionExecutor

extends Node

# 当前正在执行的 Action 队列
var action_queue=  []
var current_action_index: int = 0
var current_action: AffordanceTypes.PrimitiveAction = null

# 引用的 Agent 节点
var agent_node: Node3D = null

# 执行状态
var is_executing: bool = false
var _cancelled: bool = false
signal queue_completed(agent_id: String)
signal action_completed(action: AffordanceTypes.PrimitiveAction)


func start_queue(agent: Node3D, actions: Array) -> void:
	agent_node = agent
	action_queue = actions
	current_action_index = 0
	is_executing = true
	_cancelled = false
	_execute_next()


func cancel() -> void:
	_cancelled = true
	is_executing = false
	if is_instance_valid(agent_node) and agent_node.has_method("cancel_movement"):
		agent_node.cancel_movement("action_cancelled")


func _execute_next() -> void:
	if _cancelled:
		return
	if current_action_index >= action_queue.size():
		is_executing = false
		queue_completed.emit(agent_node.name)
		return

	current_action = action_queue[current_action_index]
	_execute_action(current_action)


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
			# 未知动作 → 跳过
			_on_action_finished()


# === 各 Primitive 的实现 ===

func _navigate(params: Dictionary) -> void:
	var target_id: String = params.get("target", "")
	if target_id.is_empty():
		_on_action_finished()
		return

	var obj = SemanticWorld.get_object(target_id)
	if not obj:
		push_warning("ActionExecutor: navigate to unknown object '%s'" % target_id)
		_on_action_finished()
		return

	await _travel_to(obj.interaction_point)
	_finish_if_active()


func _navigate_position(params: Dictionary) -> void:
	var navigation := RoomNavigation.new()
	var target := Vector3.ZERO
	var waypoint_name := String(params.get("waypoint", ""))
	if not waypoint_name.is_empty() and navigation.has_waypoint(waypoint_name):
		target = navigation.get_waypoint(waypoint_name)
	else:
		target = _to_vec3(params.get("position", Vector3.ZERO))
	if not navigation.is_safe_position(target):
		push_warning("ActionExecutor: rejected unsafe navigation target %s" % target)
		_finish_if_active()
		return
	await _travel_to(target)
	_finish_if_active()


func _patrol(params: Dictionary) -> void:
	var navigation := RoomNavigation.new()
	var route_name := String(params.get("route", "room_perimeter"))
	var laps := clampi(int(params.get("laps", 1)), 1, 3)
	var route := navigation.get_route(route_name, laps)
	if route.size() < 2:
		push_warning("ActionExecutor: patrol route '%s' is missing or too short" % route_name)
		_finish_if_active()
		return
	if agent_node.has_method("begin_locomotion_sequence"):
		agent_node.begin_locomotion_sequence()
	for target in route:
		if _cancelled:
			return
		var success := await _travel_to(target)
		if not success:
			break
	if is_instance_valid(agent_node) and agent_node.has_method("end_locomotion_sequence"):
		agent_node.end_locomotion_sequence()
	_finish_if_active()


func _wander(params: Dictionary) -> void:
	var navigation := RoomNavigation.new()
	var point_index := int(params.get("point_index", -1))
	var from_position := agent_node.global_position if is_instance_valid(agent_node) else Vector3.ZERO
	await _travel_to(navigation.get_wander_point_away(from_position, 1.0, point_index))
	_finish_if_active()


func _travel_to(target: Vector3) -> bool:
	if _cancelled or not is_instance_valid(agent_node):
		return false
	if not agent_node.has_method("move_to_position"):
		return false
	agent_node.move_to_position(target)
	while not _cancelled and is_instance_valid(agent_node) and agent_node.is_moving:
		await get_tree().process_frame
	if _cancelled or not is_instance_valid(agent_node):
		return false
	return agent_node.global_position.distance_to(target) <= 0.75


func _interact(params: Dictionary) -> void:
	var obj_id: String = params.get("object", "")
	var verb: String = params.get("verb", "")

	var obj = SemanticWorld.get_object(obj_id)
	if obj:
		# 应用交互效果到 World Simulator
		for effect_key in obj.effects:
			var need_type = _str_to_need_type(effect_key)
			if need_type != null:
				WorldSimulator.apply_effect(need_type, obj.effects[effect_key] as float)

		# 如果是消耗品 → 更新状态
		if obj.consumable and verb in ["drink", "eat"]:
			SemanticWorld.update_object_state(obj_id, "已喝完" if verb == "drink" else "已吃完")

	# 动画演示时间
	await get_tree().create_timer(1.0).timeout
	_on_action_finished()


func _speak(params: Dictionary) -> void:
	var text: String = params.get("text", "")
	var tone: String = params.get("tone", "neutral")
	if not text.is_empty():
		MessageBus.ui_show_bubble.emit(text, tone, 4.0)
	MessageBus.performance_cue.emit("talk", {"source": "executor"})
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


func _pick_up(params: Dictionary) -> void:
	await get_tree().create_timer(0.5).timeout
	_on_action_finished()


func _put_down(params: Dictionary) -> void:
	await get_tree().create_timer(0.5).timeout
	_on_action_finished()


func _sit(params: Dictionary) -> void:
	MessageBus.performance_cue.emit("sit", {"source": "executor"})
	await get_tree().create_timer(0.8).timeout
	_on_action_finished()


# === 内部 ===

func _on_action_finished() -> void:
	if _cancelled:
		return
	action_completed.emit(current_action)
	current_action_index += 1
	call_deferred("_execute_next")


func _finish_if_active() -> void:
	if not _cancelled:
		_on_action_finished()


func _to_vec3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	if value is Dictionary:
		return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))
	return Vector3.ZERO


func _str_to_need_type(str: String):
	match str:
		"hunger": return AffordanceTypes.NeedType.HUNGER
		"energy": return AffordanceTypes.NeedType.ENERGY
		"social": return AffordanceTypes.NeedType.SOCIAL
		"fun": return AffordanceTypes.NeedType.FUN
	return null
