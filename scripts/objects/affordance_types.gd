# affordance_types.gd — Primitive Actions & Affordance 枚举
# 设计文档 §四、§五

class_name AffordanceTypes

# 8 个 Primitive Actions — 所有行为由这些原子操作组合
enum Primitive {
	NAVIGATE,    # 移动到目标
	INTERACT,    # 对物体执行操作（动词来自 Affordance 表）
	SPEAK,       # 说话 + 显示气泡
	IDLE,        # 待机/微小动作
	LOOK_AT,     # 转向目标
	PICK_UP,     # 拿起物体
	PUT_DOWN,    # 放下物体
	SIT,         # 坐下/站起
}

# Agent Needs 类型 — 设计文档 §三.2
enum NeedType {
	HUNGER,
	ENERGY,
	SOCIAL,
	FUN,
	BLADDER,
}

# 游戏时间阶段
enum TimeOfDay {
	MORNING,   # 6:00-11:00
	NOON,      # 11:00-14:00
	AFTERNOON, # 14:00-18:00
	EVENING,   # 18:00-22:00
	NIGHT,     # 22:00-6:00
}

# 情绪类型
enum Emotion {
	HAPPY,
	SAD,
	ANGRY,
	SURPRISED,
	NEUTRAL,
	BORED,
	EXCITED,
	NERVOUS,
}

# 触发源类型 — 设计文档 §七.1
enum TriggerSource {
	SIMULATION,   # World Simulator 触发的状态变化
	PLAYER_INPUT, # 玩家消息/指令
	IDLE_TIMER,   # 自主定时唤醒
	SOCIAL_EVENT, # 其他 Agent 事件（预留）
}

# Primitive Action 数据结构
class PrimitiveAction:
	var type: Primitive
	var params: Dictionary = {}

	func _init(p_type: Primitive, p_params: Dictionary = {}):
		type = p_type
		params = p_params

# Agent Needs 数据
class NeedsState:
	var hunger: float = 100.0
	var energy: float = 100.0
	var social: float = 100.0
	var fun: float = 100.0
	var bladder: float = 0.0  # 0 = 不需要, 100 = 急需

	func to_dict() -> Dictionary:
		return {
			"hunger": hunger,
			"energy": energy,
			"socail": social,
			"fun": fun,
			"bladder": bladder,
		}

	func get_lowest_need() -> NeedType:
		var needs = {NeedType.HUNGER: hunger, NeedType.ENERGY: energy,
					 NeedType.SOCIAL: social, NeedType.FUN: fun}
		var lowest = NeedType.FUN
		var lowest_val = fun
		for n in needs:
			if needs[n] < lowest_val:
				lowest = n
				lowest_val = needs[n]
		return lowest
