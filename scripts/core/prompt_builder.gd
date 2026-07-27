# prompt_builder.gd — LLM prompt construction helper (RefCounted)
# Roadmap: T1, X3, T4.5
# Responsibility: Builds the structured prompt string for LLM cognition; never mutates
#   world state, scene nodes, memories or UI.
# Collaborators: CodifiedProfile, AffordanceTypes
# Tests: scripts/debug/agent_psyche_check.gd, scripts/debug/t4_5_cognitive_split_test.gd

class_name PromptBuilder
extends RefCounted


## [T1][X3][T4.5] Assemble the full LLM prompt from structured cognitive inputs.
## No side effects; returns a ready-to-send string.
func build_prompt(semantic: String, memory: String, codified: String, psychology: String, triggered: Array,
				  player_msg: String, source: AffordanceTypes.TriggerSource,
				  agent_id: String) -> String:

	var identity = CodifiedProfile.get_identity_for_agent(agent_id)
	var explicit_instruction = build_explicit_player_instruction(player_msg)
	var prompt = """%s

%s

%s

%s

[角色当前的心理与注意状态]
%s

[本轮玩家消息]
%s

[本轮约束]
%s

请根据以上信息，决定你现在要做什么。
如果当前是因为需求触发（饿了/渴了/无聊），优先满足自己的需求。
如果玩家跟你说话了，本轮玩家消息拥有最高优先级。先直接回应玩家当前所说的内容，不要被角色偏好或旧记忆带偏，也不要无故转移到奶茶。

你必须回复一个 JSON 对象，格式如下：
{"thought": "你的内心想法", "goal": "一个简洁的目标名称(如drink_milk_tea/watch_tv/read_book/rest_on_sofa/patrol_room/wander_room/chat_with_player)", "goal_reason": "为什么做这个决定", "emotion": "情绪(happy/sad/angry/surprised/neutral/bored/excited)", "emotion_intensity": 0.5, "speech": "你说的话（可以为空字符串）", "speech_tone": "语气(cheerful/neutral/nervous/sad/angry)", "gesture": "身体动作兜底(必须从以下选择一个:idle/walk/wave/nod/think/happy/sit/talk)", "motion_query": "用于动作库语义检索的短句，例如'开心地挥手问候'或'自然地走向电视'", "expression_query": "用于表情库语义检索的短句，例如'害羞但开心地笑'或'疑惑地歪头'", "plan": [{"action": "patrol", "route": "room_perimeter", "laps": 1}]}

plan 是可选字段，最多 6 步。action 只能是 navigate_object/navigate_waypoint/patrol/wander/look_at/interact/wait；目标只能引用当前场景已有物体或已知路径点。不要输出坐标。"""

	if source == AffordanceTypes.TriggerSource.SIMULATION:
		prompt += "\n\n重要提示：你需要优先满足自己的生理需求。"

	var formatted = prompt % [
		identity,
		semantic,
		memory,
		codified if not codified.is_empty() else "[没有特殊的角色反应]",
		psychology,
		player_msg if not player_msg.is_empty() else "[无，本轮为自主行为]",
		explicit_instruction,
	]

	return formatted


## [T1][C1][T4.5] Infer an explicit player goal from keyword patterns.
## Pure text inspection; no side effects.
func infer_explicit_player_goal(player_message: String) -> String:
	var message = player_message.to_lower()
	if (("绕" in message or "转" in message) and "房间" in message and "一圈" in message) or "巡逻" in message:
		return "patrol_room"
	if "随便走走" in message or "房间逛逛" in message or "走一走" in message:
		return "wander_room"
	if "看电视" in message or "开电视" in message or "电视节目" in message or "tv" in message:
		return "watch_tv"
	if "看书" in message or "读书" in message or "读小说" in message:
		return "read_book"
	if "浇花" in message or "浇水" in message or "浇植物" in message:
		return "water_plant"
	if "休息" in message or "坐沙发" in message:
		return "rest_on_sofa"
	if "喝奶茶" in message:
		return "drink_milk_tea"
	return ""


## [T1][T4.5] Build the explicit instruction line for the LLM prompt.
## Pure text assembly; no side effects.
func build_explicit_player_instruction(player_message: String) -> String:
	var goal = infer_explicit_player_goal(player_message)
	if goal.is_empty():
		return "自然、直接地回应本轮玩家消息。"
	return "玩家提出了明确可执行意图，goal 必须为 '%s'，speech 必须直接回应这项活动。" % goal


## [T1][T4.5] Verify speech acknowledges a goal; return a canned fallback if not.
## Pure text logic; no side effects.
func ensure_goal_acknowledgement(goal: String, speech: String) -> String:
	var required_keywords = {
		"patrol_room": ["绕", "巡逻", "一圈"],
		"wander_room": ["走走", "逛"],
		"watch_tv": ["电视", "节目"],
		"read_book": ["书", "小说"],
		"water_plant": ["浇", "小绿", "植物"],
		"rest_on_sofa": ["休息", "沙发", "坐"],
		"drink_milk_tea": ["奶茶", "喝"],
	}
	for keyword in required_keywords.get(goal, []):
		if keyword in speech:
			return speech
	match goal:
		"patrol_room": return "好呀，我去绕房间走一圈！"
		"wander_room": return "好呀，我在房间里随便走走～"
		"watch_tv": return "好呀，我们一起看电视吧！"
		"read_book": return "好呀，我们一起看会儿书吧！"
		"water_plant": return "好呀，我们一起给小绿浇水吧！"
		"rest_on_sofa": return "好呀，我们去沙发上休息一下吧。"
		"drink_milk_tea": return "好呀，我们一起喝奶茶吧！"
	return speech
