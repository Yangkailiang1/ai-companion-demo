# action_executor.gd — Primitive Action 执行器
# 设计文档 §五.1: 8 个 Primitive Actions 的逐帧执行
# 负责将 GOAP 生成的 Action Chain 逐个驱动 Godot 中的角色

extends Node

# 当前正在执行的 Action 队列
var action_queue: Array[AffordanceTypes.PrimitiveAction] = []
var current_action_index: int = 0
var current_action: AffordanceTypes.PrimitiveAction = null

# 引用的 Agent 节点
var agent_node: Node3D = null

# 执行状态
var is_executing: bool = false
signal queue_completed(agent_id: String)
signal action_completed(action: AffordanceTypes.PrimitiveAction)


func start_queue(agent: Node3D, actions: Array[AffordanceTypes.PrimitiveAction]) -> void:
	agent_node = agent
	action_queue = actions
	current_action_index = 0
	is_executing = true
	_execute_next()


func _execute_next() -> void:
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

	if agent_node and agent_node.has_method("move_to"):
		agent_node.move_to(obj.interaction_point)
		# 等待到达信号
		if agent_node.has_signal("arrived"):
			await agent_node.arrived
		else:
			await get_tree().create_timer(1.5).timeout
	else:
		await get_tree().create_timer(1.0).timeout

	_on_action_finished()


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
	await get_tree().create_timer(0.8).timeout
	_on_action_finished()


# === 内部 ===

func _on_action_finished() -> void:
	action_completed.emit(current_action)
	current_action_index += 1
	call_deferred("_execute_next")


func _str_to_need_type(str: String):
	match str:
		"hunger": return AffordanceTypes.NeedType.HUNGER
		"energy": return AffordanceTypes.NeedType.ENERGY
		"social": return AffordanceTypes.NeedType.SOCIAL
		"fun": return AffordanceTypes.NeedType.FUN
	return null
