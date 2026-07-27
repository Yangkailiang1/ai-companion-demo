# message_bus.gd — 统一事件总线 (Autoload)
# 设计文档 §八
# 所有 Agent / Player / World / UI 之间的事件路由
# 合并了原 SignalBus 的 emit_actions 信号，减少 Autoload 数量

extends Node

# 信号：世界状态变化
signal world_state_changed(change_type: String, data: Dictionary)

# 信号：玩家输入
signal player_message_received(text: String, is_command: bool)
signal player_attention_requested(agent_id: String, text: String)

# 信号：Agent 需要认知循环处理
signal agent_trigger_cycle(agent_id: String, source: AffordanceTypes.TriggerSource, data: Dictionary)

# 信号：Agent 完成动作
signal agent_action_completed(agent_id: String, action: Dictionary)
signal action_queue_completed(agent_id: String)
signal agent_activity_started(agent_id: String, activity_id: String, context: Dictionary)
signal agent_activity_completed(agent_id: String, activity_id: String, context: Dictionary)
signal agent_activity_interrupted(agent_id: String, activity_id: String, reason: String)
signal agent_reflection_requested(agent_id: String, recent_episodes: Array)

# 信号：GOAP Action Chain 下发（原 SignalBus.emit_actions）
signal emit_actions(agent_id: String, actions: Array)

# 信号：UI 更新请求
signal ui_show_bubble(text: String, emotion: String, duration: float)
signal agent_show_bubble(agent_id: String, text: String, emotion: String, duration: float)
signal ui_add_chat_entry(speaker: String, text: String, is_player: bool)
signal ui_update_hud(hud_data: Dictionary)
signal ui_status_changed(message: String, state: String)

# 信号：角色语音输出请求。TTSService 监听这个信号并异步播放音频。
signal tts_speech_requested(text: String, context: Dictionary)
signal agent_spoke(agent_id: String, text: String, emotion: String)

# 信号：GOAP 任务完成
signal goal_completed(agent_id: String, goal: String)

# 信号：需求阈值触发
signal need_threshold_reached(agent_id: String, need_type: AffordanceTypes.NeedType, value: float)

# 信号：表现层 cue（CharacterAnimationDriver 监听）
# gesture: "idle"|"walk"|"wave"|"nod"|"think"|"happy"|"sit"|"talk"
signal performance_cue(gesture: String, context: Dictionary)

# 表情层 cue 独立于身体动画，避免表情切换打断移动/动作。
signal expression_cue(expression: String, intensity: float, context: Dictionary)

# 表情混合 cue：允许检索层直接下发 morph 权重组合，例如 70% happy + 30% shy。
signal expression_blend_cue(expression_payload: Dictionary, context: Dictionary)

# 体验模式与自然语言剧本规划。
signal experience_mode_requested(mode_name: String)
signal experience_mode_changed(mode_name: String)
signal performance_script_requested(script_text: String)
signal story_plan_started(script_text: String)
signal story_plan_ready(document: Dictionary)
signal story_plan_failed(reason: String)


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS


# 信号：剧情导演请求
signal story_requested(story_id: String)

## [D1][T1] 玩家输入路由：剧情命令 → StoryDirector，普通消息 → CognitiveCycle。
## 侧效：剧情命令不进入认知循环，保持 ! 非剧情命令的兼容性。
## 信号：可能发出 ui_add_chat_entry、ui_status_changed、story_requested。
func route_player_input(text: String) -> void:
	var is_command = text.begins_with("!")
	var clean_text = text.trim_prefix("!") if is_command else text

	if _route_experience_input(text, is_command):
		return

	# [D1] 剧情命令路由：不进入 CognitiveCycle
	if is_command:
		var story_id := _parse_story_command(clean_text)
		if not story_id.is_empty():
			ui_add_chat_entry.emit("玩家", clean_text, true)
			ui_status_changed.emit("请求播放剧情: %s" % story_id, "pending")
			story_requested.emit(story_id)
			return

	var target_agent_id := _resolve_target_agent(clean_text)
	clean_text = _strip_agent_mention(clean_text)

	ui_add_chat_entry.emit("玩家", clean_text, true)
	ui_status_changed.emit("消息已发送，等待 AI 处理…", "pending")
	player_attention_requested.emit(target_agent_id, clean_text)
	player_message_received.emit(clean_text, is_command)

	var trigger_source = AffordanceTypes.TriggerSource.PLAYER_INPUT
	var data = {"text": clean_text, "is_command": is_command}
	agent_trigger_cycle.emit(target_agent_id, trigger_source, data)


## [D3][C9] 路由 !演出、!自由、!模式，以及演出模式下的自然语言剧本。
## 返回 true 表示输入已消费，不再进入角色认知循环。
func _route_experience_input(text: String, is_command: bool) -> bool:
	var clean := text.trim_prefix("!").strip_edges()
	if is_command and clean in ["自由", "free"]:
		ui_add_chat_entry.emit("系统", "切换到自由模式", false)
		experience_mode_requested.emit("free")
		return true
	if is_command and clean in ["模式", "mode"]:
		var current := "unknown"
		if has_node("/root/ExperienceModeManager"):
			current = get_node("/root/ExperienceModeManager").get_mode_name()
		ui_status_changed.emit("当前模式: %s" % current, "ready")
		return true
	if is_command and (
		clean == "演出" or clean.begins_with("演出 ")
		or clean == "performance" or clean.begins_with("performance ")
	):
		var script_text := _strip_mode_prefix(clean)
		ui_add_chat_entry.emit("玩家剧本", script_text if not script_text.is_empty() else "进入演出模式", true)
		experience_mode_requested.emit("performance")
		if script_text.is_empty():
			ui_status_changed.emit("演出模式已开启，请输入自然语言剧本", "performance")
		else:
			performance_script_requested.emit(script_text)
		return true
	if not is_command and has_node("/root/ExperienceModeManager"):
		if get_node("/root/ExperienceModeManager").is_performance_mode():
			ui_add_chat_entry.emit("玩家剧本", text, true)
			performance_script_requested.emit(text.strip_edges())
			return true
	return false


## [D3] 去除演出模式命令前缀，保留玩家原始剧本内容。
func _strip_mode_prefix(text: String) -> String:
	for prefix in ["演出", "performance"]:
		if text == prefix:
			return ""
		if text.begins_with(prefix + " "):
			return text.substr(prefix.length()).strip_edges()
	return text


## [C9][D3] 自由模式下把世界事件路由到角色；演出模式由导演独占角色控制。
func route_simulation_event(agent_id: String, event_type: String, data: Dictionary) -> void:
	world_state_changed.emit(event_type, data)
	if _is_performance_mode():
		return
	agent_trigger_cycle.emit(agent_id, AffordanceTypes.TriggerSource.SIMULATION, data)


## [C9][D3] 只在自由模式响应角色 IdleTimer，避免演出期间出现旁路认知请求。
func route_idle_wake(agent_id: String) -> void:
	if _is_performance_mode():
		return
	agent_trigger_cycle.emit(agent_id, AffordanceTypes.TriggerSource.IDLE_TIMER, {})


## [D3] 查询模式边界；管理器未加载时安全回退到自由模式。
func _is_performance_mode() -> bool:
	return (
		has_node("/root/ExperienceModeManager")
		and get_node("/root/ExperienceModeManager").is_performance_mode()
	)


# Agent 输出 → 路由到 UI
func route_agent_output(agent_id: String, speech: String, emotion: String) -> void:
	if not speech.is_empty():
		ui_show_bubble.emit(speech, emotion, 5.0)
		agent_show_bubble.emit(agent_id, speech, emotion, 5.0)
		tts_speech_requested.emit(speech, {
			"agent_id": agent_id,
			"emotion": emotion,
		})
		agent_spoke.emit(agent_id, speech, emotion)
	ui_add_chat_entry.emit(agent_id, speech, false)


## [D1] 解析 !剧情 <id> 和 !story <id> 命令，返回 story_id。
## 不匹配时返回空字符串，让路由继续正常认知流程。
func _parse_story_command(text: String) -> String:
	var normalized := text.strip_edges()
	for prefix in ["故事 ", "剧情 ", "story "]:
		if normalized.begins_with(prefix):
			return normalized.substr(prefix.length()).strip_edges()
	return ""


func _resolve_target_agent(text: String) -> String:
	var normalized := text.strip_edges()
	if normalized.begins_with("@诀") or normalized.begins_with("诀，") or normalized.begins_with("诀,") or normalized.begins_with("诀 "):
		return "jue_agent"
	if normalized.begins_with("@咕咕嘎嘎") or normalized.begins_with("咕咕嘎嘎"):
		return "main_agent"
	return "main_agent"


func _strip_agent_mention(text: String) -> String:
	var stripped := text.strip_edges()
	for prefix in ["@诀", "诀，", "诀,", "诀 ", "@咕咕嘎嘎", "咕咕嘎嘎，", "咕咕嘎嘎,", "咕咕嘎嘎 "]:
		if stripped.begins_with(prefix):
			return stripped.substr(prefix.length()).strip_edges()
	return stripped
