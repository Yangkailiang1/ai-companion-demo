# local_fallback_decider.gd — Local-rule fallback decision policy (RefCounted)
# Roadmap: T1, C1, X3
# Responsibility: Makes deterministic action/speech decisions when no LLM is available;
#   never accesses HTTP, never mutates scene nodes, positions, memories or UI.
# Collaborators: WorldSimulator, PerformanceResolver, motion_intent_router, PromptBuilder
# Tests: scripts/debug/gesture_pipeline_check.gd, scripts/debug/t4_5_cognitive_split_test.gd

class_name LocalFallbackDecider
extends RefCounted

# Local fallback response library
const FALLBACK_GREETINGS = [
	"你好呀！今天天气真好~",
	"嗨！你来啦！",
	"嘿嘿，正想找人聊聊天呢！",
	"哎呀，欢迎欢迎～"
]
const FALLBACK_IDLE_COMMENTS = [
	"嗯…有点无聊呢。",
	"（伸了个懒腰）",
	"要不要看会儿电视？",
	"那杯奶茶看起来好诱人啊…"
]
const FALLBACK_HUNGRY_COMMENTS = [
	"肚子有点饿了…那杯奶茶正好！",
	"好想喝点东西…",
]
const FALLBACK_BORED_COMMENTS = [
	"有点无聊，看看电视吧。",
	"找本书看看也不错。",
]

var _prompt_builder  # PromptBuilder (RefCounted)
var _perf_resolver   # PerformanceResolver (RefCounted)


## [T4.5] Supply shared helper references so the decider can reuse routing and acknowledgement
## without reaching into autoload internals.
func _init(prompt_builder, perf_resolver) -> void:
	_prompt_builder = prompt_builder
	_perf_resolver = perf_resolver


## [T1][C1][X3] Produce a structured fallback decision from player message, trigger source,
## codified triggers, current needs snapshot and optional trigger need_type.
## Dispatches to sub-decision helpers; never emits signals or mutates state.
## Side effects: none (returns a pure decision dict).
func decide(player_message: String, source: AffordanceTypes.TriggerSource, triggered: Array,
			needs: Dictionary, motion_router, trigger_need_type = null) -> Dictionary:
	var base := _default_decision()

	if source == AffordanceTypes.TriggerSource.PLAYER_INPUT and not player_message.is_empty():
		return _decide_player_input(player_message, triggered, motion_router, base)
	elif source == AffordanceTypes.TriggerSource.SIMULATION:
		return _decide_simulation(trigger_need_type, needs, triggered, base)
	elif source == AffordanceTypes.TriggerSource.IDLE_TIMER:
		return _decide_idle_timer(needs, base)
	return base


# === Decision helpers (each returns a complete decision dict) ===

## [T1][C1] Return an empty base decision with safe defaults.
## Pure factory; no side effects.
func _default_decision() -> Dictionary:
	return {
		"speech": "",
		"goal": "idle",
		"gesture": "idle",
		"emotion": "neutral",
		"emotion_intensity": 0.65,
		"compiled_plan": [],
	}


## [C1][X3] Build a decision from a high-confidence router match.
## Delegates acknowledgement text to PromptBuilder.
## Side effects: none.
func _decide_actionable_routed(routed: Dictionary, trigger_emotion: String, base: Dictionary) -> Dictionary:
	var d := base.duplicate(true)
	d["speech"] = String(routed.get("reply", ""))
	if d["speech"].is_empty():
		d["speech"] = _prompt_builder.ensure_goal_acknowledgement(
			String(routed.get("goal", "")), "")
	d["goal"] = String(routed.get("goal", d["goal"]))
	d["gesture"] = String(routed.get("clip", d["gesture"]))
	d["emotion"] = String(routed.get("expression", d["emotion"]))
	d["emotion_intensity"] = clampf(float(routed.get("intensity", d["emotion_intensity"])), 0.0, 1.0)
	if routed.get("plan", []) is Array and not routed.get("plan", []).is_empty():
		d["compiled_plan"] = PlanValidator.new().compile(routed.get("plan", []))
	return d


## [T1][C1][X3] Decide response for a player input trigger using router + keyword fallback.
## Tries motion router first; falls back to a keyword chain.
## Side effects: none.
func _decide_player_input(player_message: String, triggered: Array,
						  motion_router, base: Dictionary) -> Dictionary:
	var d := base.duplicate(true)
	var msg_lower = player_message.to_lower()
	var routed: Dictionary = _perf_resolver.route_player_intent(
		player_message, d["gesture"], d["emotion"], d["emotion_intensity"], motion_router)
	var routed_is_actionable: bool = _perf_resolver.is_actionable_router_decision(routed)

	# Apply codified emotion overrides
	if not triggered.is_empty():
		d["emotion"] = triggered[0].get("emotion", d["emotion"])

	# Router-delegated path
	if routed_is_actionable:
		return _decide_actionable_routed(routed, d["emotion"], d)

	var motion_decision := _decide_motion_keyword(msg_lower, d)
	if not motion_decision.is_empty():
		return motion_decision
	return _decide_conversation_keyword(msg_lower, d)


## [T1][C1] Resolve locomotion and explicit body-gesture keywords after router rejection.
## Returns an empty dictionary when the text does not match this keyword group.
func _decide_motion_keyword(msg_lower: String, base: Dictionary) -> Dictionary:
	var d := base.duplicate(true)
	if ("绕" in msg_lower or "转" in msg_lower) and "房间" in msg_lower and ("一圈" in msg_lower or "巡逻" in msg_lower):
		d["speech"] = "好呀，我去绕房间走一圈！"
		d["goal"] = "patrol_room"
		d["gesture"] = "walk"
		d["emotion"] = "happy"
	elif "巡逻" in msg_lower:
		d["speech"] = "收到，我去房间里巡逻一圈。"
		d["goal"] = "patrol_room"
		d["gesture"] = "walk"
	elif "随便走走" in msg_lower or "逛逛" in msg_lower or "走一走" in msg_lower:
		d["speech"] = "好呀，我在房间里随便逛逛～"
		d["goal"] = "wander_room"
		d["gesture"] = "walk"
	elif "挥挥" in msg_lower and "手" in msg_lower:
		d["speech"] = "嗨嗨，我在挥手呢～"
		d["gesture"] = "wave"
		d["emotion"] = "happy"
	elif "点点" in msg_lower and "头" in msg_lower:
		d["speech"] = "嗯嗯！我点点头～"
		d["gesture"] = "nod"
		d["emotion"] = "happy"
	elif "想一想" in msg_lower or "想想" in msg_lower:
		d["speech"] = "让我想一想……（思考中）"
		d["gesture"] = "think"
		d["emotion"] = "neutral"
	elif "开心" in msg_lower and "一点" in msg_lower:
		d["speech"] = "好嘞！开心起来～"
		d["gesture"] = "happy"
		d["emotion"] = "happy"
	else:
		return {}
	return d


## [T1][C1][X3] Resolve conversational and object-activity keywords after router rejection.
## Falls back to a lightweight generic acknowledgement when no keyword matches.
func _decide_conversation_keyword(msg_lower: String, base: Dictionary) -> Dictionary:
	var d := base.duplicate(true)
	if "你好" in msg_lower or "嗨" in msg_lower or "hi" in msg_lower:
		d["speech"] = FALLBACK_GREETINGS[randi() % FALLBACK_GREETINGS.size()]
		d["emotion"] = "happy"
	elif "饿" in msg_lower or "吃" in msg_lower:
		d["speech"] = "对呀对呀，要不要一起喝杯奶茶？"
		d["goal"] = "drink_milk_tea"
		d["emotion"] = "excited"
	elif "玩" in msg_lower or "无聊" in msg_lower:
		d["speech"] = "嗯嗯！我们找点事情做吧！"
		d["emotion"] = "happy"
	elif "再见" in msg_lower or "拜拜" in msg_lower:
		d["speech"] = "好的，下次再来找我玩哦～"
		d["emotion"] = "neutral"
	elif "开电视" in msg_lower or "看电视" in msg_lower or "tv" in msg_lower:
		d["speech"] = "好呀！我们一起看电视，我来找找遥控器～"
		d["goal"] = "watch_tv"
		d["emotion"] = "happy"
	elif "浇" in msg_lower and "植物" in msg_lower or "花" in msg_lower:
		d["speech"] = "对哦，小绿好像缺水了，我来浇一下！"
		d["goal"] = "water_plant"
		d["emotion"] = "happy"
	elif "看书" in msg_lower or "读书" in msg_lower:
		d["speech"] = "好呀，一起看看书！"
		d["goal"] = "read_book"
		d["emotion"] = "happy"
	elif "坐" in msg_lower or "休息" in msg_lower:
		d["speech"] = "好的，休息一下～"
		d["goal"] = "rest_on_sofa"
		d["emotion"] = "neutral"
	else:
		d["speech"] = "嗯嗯，我听到了！" if randi() % 2 == 0 else "哈哈，你说得对～"
		d["emotion"] = "happy" if randf() > 0.5 else "neutral"
	return d


## [T1][C1][X3] Decide for a SIMULATION trigger using need_type filtering.
## Only a HUNGER trigger can choose hunger fallback; only a FUN trigger can choose
## fun/bored fallback.  Falls through to codified reaction otherwise.
## Side effects: none.
func _decide_simulation(trigger_need_type: Variant, needs: Dictionary, triggered: Array,
						base: Dictionary) -> Dictionary:
	var d := base.duplicate(true)

	# Restore exact old semantics: need_type filters what fallback can fire
	if trigger_need_type == AffordanceTypes.NeedType.HUNGER and _is_need_low(needs, "hunger", 40):
		d["speech"] = FALLBACK_HUNGRY_COMMENTS[randi() % FALLBACK_HUNGRY_COMMENTS.size()]
		d["goal"] = "drink_milk_tea"
	elif trigger_need_type == AffordanceTypes.NeedType.FUN and _is_need_low(needs, "fun", 30):
		d["speech"] = FALLBACK_BORED_COMMENTS[randi() % FALLBACK_BORED_COMMENTS.size()]
		d["goal"] = "watch_tv"
	elif not triggered.is_empty():
		d["speech"] = triggered[0].get("reaction", "")
		d["emotion"] = triggered[0].get("emotion", d["emotion"])
	return d


## [T1][X3] Decide for an IDLE_TIMER trigger using need levels + random chatter.
## Side effects: none.
func _decide_idle_timer(needs: Dictionary, base: Dictionary) -> Dictionary:
	var d := base.duplicate(true)

	if _is_need_low(needs, "hunger", 40):
		d["speech"] = FALLBACK_HUNGRY_COMMENTS[randi() % FALLBACK_HUNGRY_COMMENTS.size()]
		d["goal"] = "drink_milk_tea"
	elif _is_need_low(needs, "fun", 30):
		d["speech"] = FALLBACK_BORED_COMMENTS[randi() % FALLBACK_BORED_COMMENTS.size()]
		d["goal"] = "watch_tv"
	elif randf() < 0.12:
		d["goal"] = "wander_room"
	elif randf() < 0.1:
		d["speech"] = FALLBACK_IDLE_COMMENTS[randi() % FALLBACK_IDLE_COMMENTS.size()]
	return d


## [X3] Check whether a named need is below a threshold.
## Pure query; no side effects.
func _is_need_low(needs: Dictionary, need_name: String, threshold: float) -> bool:
	return needs.get(need_name, 100.0) < threshold
