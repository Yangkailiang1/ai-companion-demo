# world_simulator.gd — 世界仿真引擎 (Autoload)
# 设计文档 §三：时间流逝 / Agent需求 / 确定性物理规则
# 所有数据变化由 Simulator 计算，LLM 只负责语义推理

extends Node

signal game_hour_advanced(day: int, hour: float)

# 时间系统
var game_time: float = 8.0        # 游戏小时（0-24，8 = 早上8点）
var day_number: int = 1           # 游戏天数
var time_of_day: AffordanceTypes.TimeOfDay = AffordanceTypes.TimeOfDay.MORNING

# 时间流速：现实 5 分钟 = 游戏 1 小时。
# accumulator 的单位是“游戏小时”，因此每个现实秒只推进 1/300 小时。
const GAME_HOURS_PER_REAL_SECOND: float = 1.0 / 300.0
var time_accumulator: float = 0.0

# Agent Needs 状态
var agent_needs: AffordanceTypes.NeedsState
var agent_needs_by_id: Dictionary = {}

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
	AffordanceTypes.NeedType.HUNGER: 30.0,
	AffordanceTypes.NeedType.ENERGY: 20.0,
	AffordanceTypes.NeedType.SOCIAL: 20.0,
	AffordanceTypes.NeedType.FUN: 20.0,
	AffordanceTypes.NeedType.BLADDER: 80.0,
}

# 阈值触发冷却（防止每个 game hour 都触发）
var _last_threshold_trigger: Dictionary = {}


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	agent_needs = AffordanceTypes.NeedsState.new()
	agent_needs_by_id = {
		"main_agent": agent_needs,
		"jue_agent": AffordanceTypes.NeedsState.new(),
	}


func _process(delta: float) -> void:
	# 时间流逝
	time_accumulator += delta * GAME_HOURS_PER_REAL_SECOND
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

	# 检查是否需要触发 Agent（需求低于阈值，带冷却）
	_check_need_thresholds()
	game_hour_advanced.emit(day_number, game_time)


func _apply_need_decay() -> void:
	for state_value in agent_needs_by_id.values():
		var state: AffordanceTypes.NeedsState = state_value
		state.hunger = clamp(state.hunger - NEED_DECAY[AffordanceTypes.NeedType.HUNGER], 0, 100)
		state.energy = clamp(state.energy - NEED_DECAY[AffordanceTypes.NeedType.ENERGY], 0, 100)
		state.social = clamp(state.social - NEED_DECAY[AffordanceTypes.NeedType.SOCIAL], 0, 100)
		state.fun = clamp(state.fun - NEED_DECAY[AffordanceTypes.NeedType.FUN], 0, 100)
		state.bladder = clamp(state.bladder + NEED_DECAY[AffordanceTypes.NeedType.BLADDER], 0, 100)


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

		if not triggered:
			continue

		# 冷却检查：每种 need type 至少间隔 30 game hours 才重复触发
		var now = Time.get_unix_time_from_system()
		var last_trigger = _last_threshold_trigger.get(need_type, 0.0) as float
		if now - last_trigger < 120.0:  # 至少 2 分钟真实时间
			continue
		_last_threshold_trigger[need_type] = now

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
	var needs := get_needs_for_agent(agent_id)
	match need_type:
		AffordanceTypes.NeedType.HUNGER: needs.hunger = clamp(needs.hunger + delta_val, 0, 100)
		AffordanceTypes.NeedType.ENERGY: needs.energy = clamp(needs.energy + delta_val, 0, 100)
		AffordanceTypes.NeedType.SOCIAL: needs.social = clamp(needs.social + delta_val, 0, 100)
		AffordanceTypes.NeedType.FUN: needs.fun = clamp(needs.fun + delta_val, 0, 100)


func get_needs_for_agent(agent_id: String) -> AffordanceTypes.NeedsState:
	var normalized := agent_id if not agent_id.is_empty() else "main_agent"
	if not agent_needs_by_id.has(normalized):
		agent_needs_by_id[normalized] = AffordanceTypes.NeedsState.new()
	return agent_needs_by_id[normalized]


# 获取当前世界状态快照（给 SemanticWorld 使用）
func get_state_snapshot() -> Dictionary:
	return {
		"game_time": game_time,
		"day": day_number,
		"time_of_day": _time_of_day_str(),
		"needs": agent_needs.to_dict(),
		"agent_needs": _serialize_agent_needs(),
	}


func export_save_state() -> Dictionary:
	return {
		"game_time": game_time,
		"day_number": day_number,
		"time_accumulator": time_accumulator,
		"needs": agent_needs.to_dict(),
		"agent_needs": _serialize_agent_needs(),
	}


func import_save_state(data: Dictionary) -> void:
	game_time = clampf(float(data.get("game_time", game_time)), 0.0, 23.999)
	day_number = maxi(int(data.get("day_number", day_number)), 1)
	time_accumulator = clampf(float(data.get("time_accumulator", 0.0)), 0.0, 0.999)
	var needs: Dictionary = data.get("needs", {})
	agent_needs.hunger = clampf(float(needs.get("hunger", agent_needs.hunger)), 0.0, 100.0)
	agent_needs.energy = clampf(float(needs.get("energy", agent_needs.energy)), 0.0, 100.0)
	agent_needs.social = clampf(float(needs.get("social", agent_needs.social)), 0.0, 100.0)
	agent_needs.fun = clampf(float(needs.get("fun", agent_needs.fun)), 0.0, 100.0)
	agent_needs.bladder = clampf(float(needs.get("bladder", agent_needs.bladder)), 0.0, 100.0)
	var saved_agent_needs: Dictionary = data.get("agent_needs", {})
	for saved_agent_id in saved_agent_needs:
		_import_needs_state(get_needs_for_agent(String(saved_agent_id)), saved_agent_needs[saved_agent_id])
	time_of_day = _calculate_time_of_day()


func _serialize_agent_needs() -> Dictionary:
	var serialized := {}
	for saved_agent_id in agent_needs_by_id:
		var state: AffordanceTypes.NeedsState = agent_needs_by_id[saved_agent_id]
		serialized[String(saved_agent_id)] = state.to_dict()
	return serialized


func _import_needs_state(state: AffordanceTypes.NeedsState, data: Dictionary) -> void:
	state.hunger = clampf(float(data.get("hunger", state.hunger)), 0.0, 100.0)
	state.energy = clampf(float(data.get("energy", state.energy)), 0.0, 100.0)
	state.social = clampf(float(data.get("social", state.social)), 0.0, 100.0)
	state.fun = clampf(float(data.get("fun", state.fun)), 0.0, 100.0)
	state.bladder = clampf(float(data.get("bladder", state.bladder)), 0.0, 100.0)
