# world_simulator.gd — 世界仿真引擎 (Autoload)
# 设计文档 §三：时间流逝 / Agent需求 / 确定性物理规则
# 所有数据变化由 Simulator 计算，LLM 只负责语义推理

extends Node

# 时间系统
var game_time: float = 8.0        # 游戏小时（0-24，8 = 早上8点）
var day_number: int = 1           # 游戏天数
var time_of_day: AffordanceTypes.TimeOfDay = AffordanceTypes.TimeOfDay.MORNING

# 时间流速：现实 5 分钟 = 游戏 1 小时 → ratio = 12
const TIME_RATIO: float = 12.0
var time_accumulator: float = 0.0

# Agent Needs 状态
var agent_needs: AffordanceTypes.NeedsState

# 每游戏小时的变化量
const NEED_DECAY := {
	AffordanceTypes.NeedType.HUNGER: 5.0,
	AffordanceTypes.NeedType.ENERGY: 3.0,
	AffordanceTypes.NeedType.SOCIAL: 2.0,
	AffordanceTypes.NeedType.FUN: 3.0,
	AffordanceTypes.NeedType.BLADDER: 8.0,
}

# 需求阈值：触发 Agent 认知循环
const NEED_THRESHOLD := {
	AffordanceTypes.NeedType.HUNGER: 30.0,   # 低于30 → 饿了
	AffordanceTypes.NeedType.ENERGY: 20.0,   # 低于20 → 困了
	AffordanceTypes.NeedType.SOCIAL: 20.0,   # 低于20 → 想聊天
	AffordanceTypes.NeedType.FUN: 20.0,      # 低于20 → 找事做
	AffordanceTypes.NeedType.BLADDER: 80.0,  # 高于80 → 需要去厕所
}


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	agent_needs = AffordanceTypes.NeedsState.new()


func _process(delta: float) -> void:
	# 时间流逝
	time_accumulator += delta * TIME_RATIO
	while time_accumulator >= 1.0:
		time_accumulator -= 1.0
		_advance_one_game_hour()


func _advance_one_game_hour() -> void:
	game_time += 1.0
	if game_time >= 24.0:
		game_time -= 24.0
		day_number += 1

	# 更新需求（每游戏小时衰减）
	_apply_need_decay()

	# 更新时间阶段
	var new_tod = _calculate_time_of_day()
	if new_tod != time_of_day:
		time_of_day = new_tod
		MessageBus.world_state_changed.emit("time_of_day_changed", {
			"time_of_day": _time_of_day_str(),
			"game_time": game_time,
			"day": day_number
		})

	# 检查是否需要触发 Agent（需求低于阈值）
	_check_need_thresholds()


func _apply_need_decay() -> void:
	agent_needs.hunger = clamp(agent_needs.hunger - NEED_DECAY[AffordanceTypes.NeedType.HUNGER], 0, 100)
	agent_needs.energy = clamp(agent_needs.energy - NEED_DECAY[AffordanceTypes.NeedType.ENERGY], 0, 100)
	agent_needs.social = clamp(agent_needs.social - NEED_DECAY[AffordanceTypes.NeedType.SOCIAL], 0, 100)
	agent_needs.fun = clamp(agent_needs.fun - NEED_DECAY[AffordanceTypes.NeedType.FUN], 0, 100)
	agent_needs.bladder = clamp(agent_needs.bladder + NEED_DECAY[AffordanceTypes.NeedType.BLADDER], 0, 100)


func _check_need_thresholds() -> void:
	for need_type in NEED_THRESHOLD:
		var value: float
		match need_type:
			AffordanceTypes.NeedType.HUNGER: value = agent_needs.hunger
			AffordanceTypes.NeedType.ENERGY: value = agent_needs.energy
			AffordanceTypes.NeedType.SOCIAL: value = agent_needs.social
			AffordanceTypes.NeedType.FUN: value = agent_needs.fun
			AffordanceTypes.NeedType.BLADDER: value = agent_needs.bladder

		var threshold = NEED_THRESHOLD[need_type]
		var triggered = (need_type == AffordanceTypes.NeedType.BLADDER) and (value >= threshold)
		triggered = triggered or ((need_type != AffordanceTypes.NeedType.BLADDER) and (value <= threshold))

		if triggered:
			MessageBus.route_simulation_event("main_agent", "need_threshold", {
				"need_type": need_type,
				"value": value,
				"threshold": threshold
			})


func _calculate_time_of_day() -> AffordanceTypes.TimeOfDay:
	if game_time >= 6 and game_time < 11:
		return AffordanceTypes.TimeOfDay.MORNING
	elif game_time >= 11 and game_time < 14:
		return AffordanceTypes.TimeOfDay.NOON
	elif game_time >= 14 and game_time < 18:
		return AffordanceTypes.TimeOfDay.AFTERNOON
	elif game_time >= 18 and game_time < 22:
		return AffordanceTypes.TimeOfDay.EVENING
	else:
		return AffordanceTypes.TimeOfDay.NIGHT


func _time_of_day_str() -> String:
	match time_of_day:
		AffordanceTypes.TimeOfDay.MORNING: return "早晨"
		AffordanceTypes.TimeOfDay.NOON: return "中午"
		AffordanceTypes.TimeOfDay.AFTERNOON: return "下午"
		AffordanceTypes.TimeOfDay.EVENING: return "傍晚"
		AffordanceTypes.TimeOfDay.NIGHT: return "夜晚"
	return "未知"


# 外部调用：某个动作对需求的影响
func apply_effect(need_type: AffordanceTypes.NeedType, delta_val: float, agent_id: String = "main_agent") -> void:
	match need_type:
		AffordanceTypes.NeedType.HUNGER: agent_needs.hunger = clamp(agent_needs.hunger + delta_val, 0, 100)
		AffordanceTypes.NeedType.ENERGY: agent_needs.energy = clamp(agent_needs.energy + delta_val, 0, 100)
		AffordanceTypes.NeedType.SOCIAL: agent_needs.social = clamp(agent_needs.social + delta_val, 0, 100)
		AffordanceTypes.NeedType.FUN: agent_needs.fun = clamp(agent_needs.fun + delta_val, 0, 100)


# 获取当前世界状态快照（给 SemanticWorld 使用）
func get_state_snapshot() -> Dictionary:
	return {
		"game_time": game_time,
		"day": day_number,
		"time_of_day": _time_of_day_str(),
		"needs": agent_needs.to_dict(),
	}
