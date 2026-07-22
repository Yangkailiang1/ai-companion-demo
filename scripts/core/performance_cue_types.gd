# performance_cue_types.gd — Performance Cue 类型定义
# 统一的角色表现 cue 协议
# 设计文档 CHARACTER_ACTION_PIPELINE.md

class_name PerformanceCueTypes

# 受限 gesture 枚举 — 与 LLM JSON schema 的 gesture 字段一一对应
enum Gesture {
	IDLE,    # 待机 (breathing/sway)
	WALK,    # 行走 (in-place cycle)
	WAVE,    # 挥手
	NOD,     # 点头
	THINK,   # 思考 (head tilt + hand to chin)
	HAPPY,   # 开心 (bounce + arms up)
	SIT,     # 坐下 (leg fold)
	TALK,    # 说话 (mouth/mild body animation — 本轮用 idle 变体)
	OFFLINE_SMOKE_WALK, # 离线 HumanML3D retarget smoke clip
}

# gesture 名称到枚举值字符串的映射（供校验和序列化）
const GESTURE_NAMES: Dictionary = {
	"idle":  Gesture.IDLE,
	"walk":  Gesture.WALK,
	"wave":  Gesture.WAVE,
	"nod":   Gesture.NOD,
	"think": Gesture.THINK,
	"happy": Gesture.HAPPY,
	"sit":   Gesture.SIT,
	"talk":  Gesture.TALK,
	"offline_smoke_walk": Gesture.OFFLINE_SMOKE_WALK,
}

# 有效的 gesture 名称列表（供 JSON schema 生成和校验）
const VALID_GESTURES: PackedStringArray = [
	"idle", "walk", "wave", "nod", "think", "happy", "sit", "talk", "offline_smoke_walk"
]


# 校验未知 gesture
static func is_valid_gesture(name: String) -> bool:
	return name in GESTURE_NAMES


# 将字符串转为 Gesture 枚举
static func parse_gesture(name: String) -> int:
	if name in GESTURE_NAMES:
		return GESTURE_NAMES[name]
	return Gesture.IDLE


# 将 Gesture 枚举转为字符串（用于 AnimationLibrary 查找）
static func gesture_to_string(gesture: int) -> String:
	match gesture:
		Gesture.IDLE:  return "idle"
		Gesture.WALK:  return "walk"
		Gesture.WAVE:  return "wave"
		Gesture.NOD:   return "nod"
		Gesture.THINK: return "think"
		Gesture.HAPPY: return "happy"
		Gesture.SIT:   return "sit"
		Gesture.TALK:  return "talk"
		Gesture.OFFLINE_SMOKE_WALK: return "offline_smoke_walk"
	return "idle"
