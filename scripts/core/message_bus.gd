# message_bus.gd — 统一事件总线 (Autoload)
# 设计文档 §八
# 所有 Agent / Player / World / UI 之间的事件路由
# 合并了原 SignalBus 的 emit_actions 信号，减少 Autoload 数量

extends Node

# 信号：世界状态变化
signal world_state_changed(change_type: String, data: Dictionary)

# 信号：玩家输入
signal player_message_received(text: String, is_command: bool)

# 信号：Agent 需要认知循环处理
signal agent_trigger_cycle(agent_id: String, source: AffordanceTypes.TriggerSource, data: Dictionary)

# 信号：Agent 完成动作
signal agent_action_completed(agent_id: String, action: Dictionary)

# 信号：GOAP Action Chain 下发（原 SignalBus.emit_actions）
signal emit_actions(agent_id: String, actions: Array)

# 信号：UI 更新请求
signal ui_show_bubble(text: String, emotion: String, duration: float)
signal ui_add_chat_entry(speaker: String, text: String, is_player: bool)
signal ui_update_hud(hud_data: Dictionary)
signal ui_status_changed(message: String, state: String)

# 信号：GOAP 任务完成
signal goal_completed(agent_id: String, goal: String)

# 信号：需求阈值触发
signal need_threshold_reached(agent_id: String, need_type: AffordanceTypes.NeedType, value: float)

# 信号：表现层 cue（CharacterAnimationDriver 监听）
# gesture: "idle"|"walk"|"wave"|"nod"|"think"|"happy"|"sit"|"talk"
signal performance_cue(gesture: String, context: Dictionary)

# 表情层 cue 独立于身体动画，避免表情切换打断移动/动作。
signal expression_cue(expression: String, intensity: float, context: Dictionary)


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS


# 玩家发送消息 → 路由到 Agent
func route_player_input(text: String) -> void:
	var is_command = text.begins_with("!")
	var clean_text = text.trim_prefix("!") if is_command else text

	ui_add_chat_entry.emit("玩家", clean_text, true)
	ui_status_changed.emit("消息已发送，等待 AI 处理…", "pending")

	var trigger_source = AffordanceTypes.TriggerSource.PLAYER_INPUT
	var data = {"text": clean_text, "is_command": is_command}
	agent_trigger_cycle.emit("main_agent", trigger_source, data)


# World Simulator 事件 → 路由到 Agent
func route_simulation_event(agent_id: String, event_type: String, data: Dictionary) -> void:
	world_state_changed.emit(event_type, data)
	agent_trigger_cycle.emit(agent_id, AffordanceTypes.TriggerSource.SIMULATION, data)


# Idle Timer → 路由到 Agent
func route_idle_wake(agent_id: String) -> void:
	agent_trigger_cycle.emit(agent_id, AffordanceTypes.TriggerSource.IDLE_TIMER, {})


# Agent 输出 → 路由到 UI
func route_agent_output(agent_id: String, speech: String, emotion: String) -> void:
	if not speech.is_empty():
		ui_show_bubble.emit(speech, emotion, 5.0)
	ui_add_chat_entry.emit(agent_id, speech, false)
