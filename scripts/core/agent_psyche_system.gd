# Persistent, lightweight psychology for believable Agent behavior.
# Implements OCEAN/motive modulation, decaying mood, intention continuity and
# a bounded Theory-of-Mind belief model. It never controls physical execution.

extends Node

const CONFIG_PATH := "res://data/agent_psychology.json"
const MOOD_RETURN_RATE := 0.035
const MAX_PRIVATE_THOUGHTS := 12
const MAX_RECENT_ACTIVITIES := 6

var _profiles: Dictionary = {}
var _states: Dictionary = {}
var _mood_tick_accumulator := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_profiles()
	for agent_id in _profiles:
		_ensure_state(String(agent_id))
	MessageBus.player_attention_requested.connect(_on_player_attention_requested)
	MessageBus.agent_activity_started.connect(_on_activity_started)
	MessageBus.agent_activity_completed.connect(_on_activity_completed)
	MessageBus.agent_activity_interrupted.connect(_on_activity_interrupted)
	MessageBus.agent_spoke.connect(_on_agent_spoke)
	MessageBus.agent_reflection_requested.connect(_on_reflection_requested)


func _process(delta: float) -> void:
	_mood_tick_accumulator += delta
	if _mood_tick_accumulator < 1.0:
		return
	var elapsed := _mood_tick_accumulator
	_mood_tick_accumulator = 0.0
	for agent_id in _states:
		var state: Dictionary = _states[agent_id]
		var baseline: Dictionary = _profile(String(agent_id)).get("baseline_mood", {})
		var mood: Dictionary = state["mood"]
		var blend := 1.0 - exp(-MOOD_RETURN_RATE * elapsed)
		mood["valence"] = lerpf(float(mood["valence"]), float(baseline.get("valence", 0.0)), blend)
		mood["arousal"] = lerpf(float(mood["arousal"]), float(baseline.get("arousal", 0.4)), blend)


func get_utility_modifier(agent_id: String, activity_id: String) -> float:
	var state := _ensure_state(agent_id)
	var profile := _profile(agent_id)
	var traits: Dictionary = profile.get("traits", {})
	var motives: Dictionary = profile.get("motives", {})
	var mood: Dictionary = state["mood"]
	var modifier := 0.72
	match activity_id:
		"plant_care":
			modifier += 0.22 * _value(traits, "conscientiousness")
			modifier += 0.18 * _value(traits, "agreeableness")
			modifier += 0.24 * _value(motives, "care")
		"read_book":
			modifier += 0.22 * _value(traits, "openness")
			modifier += 0.26 * _value(motives, "curiosity")
			modifier += 0.12 * (1.0 - float(mood.get("arousal", 0.4)))
		"rest_on_sofa":
			modifier += 0.2 * _value(motives, "comfort")
			modifier += 0.1 * _value(traits, "neuroticism")
			modifier += 0.12 * float(mood.get("arousal", 0.4))
		"wander_room":
			modifier += 0.18 * _value(traits, "openness")
			modifier += 0.2 * _value(traits, "extraversion")
			modifier += 0.18 * _value(motives, "autonomy")
			modifier += 0.1 * float(mood.get("arousal", 0.4))
		_:
			modifier = 1.0
	var recent: Array = state.get("recent_activities", [])
	if not recent.is_empty() and String(recent[-1]) == activity_id:
		modifier *= 0.68
	elif activity_id in recent:
		modifier *= 0.86
	return clampf(modifier, 0.45, 1.5)


func get_utility_reason(agent_id: String, activity_id: String) -> String:
	var state := _ensure_state(agent_id)
	var mood: Dictionary = state["mood"]
	var profile := _profile(agent_id)
	var motives: Dictionary = profile.get("motives", {})
	var dominant_motive := "autonomy"
	for motive in motives:
		if float(motives[motive]) > float(motives.get(dominant_motive, 0.0)):
			dominant_motive = String(motive)
	return "mood=%s motive=%s recent=%s activity=%s" % [
		_mood_label(mood),
		dominant_motive,
		state.get("recent_activities", []),
		activity_id,
	]


func get_schedule_modifier(agent_id: String, activity_id: String) -> float:
	_refresh_daily_plan(agent_id)
	var profile := _profile(agent_id)
	var rhythm: Dictionary = profile.get("daily_rhythm", {})
	var period := _time_period_key()
	var period_weights: Dictionary = rhythm.get(period, {})
	return clampf(float(period_weights.get(activity_id, 1.0)), 0.4, 1.6)


func get_daily_plan(agent_id: String) -> Dictionary:
	_refresh_daily_plan(agent_id)
	return _ensure_state(agent_id).get("daily_plan", {}).duplicate(true)


func get_agent_state(agent_id: String) -> Dictionary:
	return _ensure_state(agent_id).duplicate(true)


func get_belief(observer_id: String, target_id: String) -> Dictionary:
	var state := _ensure_state(observer_id)
	return state.get("beliefs", {}).get(target_id, {}).duplicate(true)


func build_cognitive_context(agent_id: String) -> String:
	var state := _ensure_state(agent_id)
	var mood: Dictionary = state["mood"]
	var lines: Array[String] = [
		"[持续心理状态]",
		"- 当前心境：%s（愉悦度 %.2f，唤醒度 %.2f）" % [
			_mood_label(mood),
			float(mood.get("valence", 0.0)),
			float(mood.get("arousal", 0.4)),
		],
		"- 当前注意：%s" % String(state.get("attention", "无明确对象")),
		"- 当前意图：%s" % String(state.get("intention", "无")),
		"- 最近活动：%s" % [state.get("recent_activities", [])],
		"- 当前日计划：%s" % [get_daily_plan(agent_id)],
	]
	var beliefs: Dictionary = state.get("beliefs", {})
	if not beliefs.is_empty():
		lines.append("[对其他角色的当前判断（可能不完全正确）]")
		for target_id in beliefs:
			var belief: Dictionary = beliefs[target_id]
			lines.append("- %s：%s，置信度 %.2f" % [
				CodifiedProfile.get_agent_display_name(String(target_id)),
				String(belief.get("inferred_intent", "意图不明")),
				float(belief.get("confidence", 0.0)),
			])
	lines.append("心理状态必须影响语气和选择，但不要机械地把数值或“我现在的情绪是”说出口。")
	return "\n".join(lines)


func build_graph_state(agent_id: String, trigger: Dictionary = {}) -> Dictionary:
	var profile := _profile(agent_id)
	return {
		"schema_version": 1,
		"thread_id": "agent:%s" % agent_id,
		"agent_id": agent_id,
		"trigger": trigger.duplicate(true),
		"profile": {
			"identity": CodifiedProfile.get_identity_for_agent(agent_id),
			"traits": profile.get("traits", {}).duplicate(true),
			"motives": profile.get("motives", {}).duplicate(true),
		},
		"psyche": get_agent_state(agent_id),
		"daily_plan": get_daily_plan(agent_id),
		"world": SemanticWorld.generate_semantic_snapshot(agent_id),
		"memory_context": MemorySystem.format_for_llm_for_agent(agent_id, String(trigger.get("text", ""))),
		"reflection": {},
		"candidate_goals": [],
		"selected_goal": {},
		"response": {},
	}


func export_save_state() -> Dictionary:
	return _states.duplicate(true)


func import_save_state(data: Dictionary) -> void:
	for agent_id in data:
		var incoming: Dictionary = data[agent_id]
		var state := _ensure_state(String(agent_id))
		var mood: Dictionary = incoming.get("mood", {})
		state["mood"]["valence"] = clampf(float(mood.get("valence", state["mood"]["valence"])), -1.0, 1.0)
		state["mood"]["arousal"] = clampf(float(mood.get("arousal", state["mood"]["arousal"])), 0.0, 1.0)
		state["attention"] = String(incoming.get("attention", ""))
		state["intention"] = String(incoming.get("intention", ""))
		state["beliefs"] = incoming.get("beliefs", {}).duplicate(true)
		state["recent_activities"] = incoming.get("recent_activities", []).duplicate()
		state["private_thoughts"] = incoming.get("private_thoughts", []).duplicate(true)
		state["daily_plan"] = incoming.get("daily_plan", {}).duplicate(true)


func _on_player_attention_requested(agent_id: String, text: String) -> void:
	var state := _ensure_state(agent_id)
	state["attention"] = "player"
	state["intention"] = "respond_to_player"
	var sentiment := _estimate_sentiment(text)
	_shift_mood(agent_id, sentiment * 0.12, 0.14)
	_add_private_thought(agent_id, "玩家正在对我说话，我应该先注意并回应。")
	_turn_agent_toward_camera(agent_id)
	MessageBus.performance_cue.emit("think", {
		"agent_id": agent_id,
		"source": "psyche_player_attention",
	})
	MessageBus.expression_cue.emit(
		"happy" if sentiment > 0.2 else ("sad" if sentiment < -0.2 else "neutral"),
		0.35 if absf(sentiment) < 0.2 else 0.55,
		{"agent_id": agent_id, "source": "psyche_player_attention"}
	)


func _on_activity_started(agent_id: String, activity_id: String, context: Dictionary) -> void:
	var actor_state := _ensure_state(agent_id)
	actor_state["intention"] = activity_id
	actor_state["attention"] = String(context.get("focus_target", activity_id))
	_add_private_thought(agent_id, "我决定先做%s，并在完成前保持注意。" % _activity_label(activity_id))
	for node in get_tree().get_nodes_in_group("agents"):
		var observer_id := String(node.get("agent_name"))
		if observer_id.is_empty() or observer_id == agent_id:
			continue
		var observer_state := _ensure_state(observer_id)
		observer_state["beliefs"][agent_id] = {
			"observed_activity": activity_id,
			"inferred_intent": _inferred_intent(activity_id),
			"confidence": 0.68,
			"observed_at_msec": Time.get_ticks_msec(),
		}
		observer_state["attention"] = agent_id
		if String(node.get("current_activity")) == "idle":
			_turn_agent_toward_agent(observer_id, agent_id)
			MessageBus.performance_cue.emit("idle", {
				"agent_id": observer_id,
				"source": "psyche_social_attention",
				"observed_agent": agent_id,
			})


func _on_activity_completed(agent_id: String, activity_id: String, _context: Dictionary) -> void:
	var state := _ensure_state(agent_id)
	state["intention"] = ""
	var recent: Array = state["recent_activities"]
	recent.append(activity_id)
	while recent.size() > MAX_RECENT_ACTIVITIES:
		recent.pop_front()
	_refresh_daily_plan(agent_id)
	var daily_plan: Dictionary = state["daily_plan"]
	var completed: Array = daily_plan.get("completed", [])
	completed.append(activity_id)
	daily_plan["completed"] = completed
	match activity_id:
		"plant_care": _shift_mood(agent_id, 0.14, -0.04)
		"read_book": _shift_mood(agent_id, 0.1, -0.08)
		"rest_on_sofa": _shift_mood(agent_id, 0.08, -0.18)
		"wander_room": _shift_mood(agent_id, 0.06, 0.08)
	_add_private_thought(agent_id, "我完成了%s，接下来不必立刻重复。" % _activity_label(activity_id))


func _on_activity_interrupted(agent_id: String, activity_id: String, reason: String) -> void:
	var state := _ensure_state(agent_id)
	state["intention"] = "respond_to_player" if reason == "player" else ""
	_shift_mood(agent_id, -0.025, 0.08)
	_add_private_thought(agent_id, "%s被%s打断，我需要重新安排。" % [_activity_label(activity_id), reason])


func _on_agent_spoke(agent_id: String, _text: String, emotion: String) -> void:
	match emotion:
		"happy", "excited": _shift_mood(agent_id, 0.08, 0.06)
		"sad": _shift_mood(agent_id, -0.1, -0.03)
		"angry": _shift_mood(agent_id, -0.12, 0.15)
		_:
			_shift_mood(agent_id, 0.01, 0.01)


func _on_reflection_requested(agent_id: String, recent_episodes: Array) -> void:
	var state := _ensure_state(agent_id)
	var activity_counts := {}
	var player_mentions := 0
	for episode in recent_episodes:
		var content := String(episode.get("content", ""))
		if "玩家" in content:
			player_mentions += 1
		for activity_id in ["plant_care", "read_book", "rest_on_sofa", "wander_room"]:
			if _activity_label(activity_id) in content or activity_id in content:
				activity_counts[activity_id] = int(activity_counts.get(activity_id, 0)) + 1
	var dominant_activity := ""
	for activity_id in activity_counts:
		if int(activity_counts[activity_id]) > int(activity_counts.get(dominant_activity, 0)):
			dominant_activity = String(activity_id)
	var mood: Dictionary = state["mood"]
	var parts: Array[String] = []
	if not dominant_activity.is_empty():
		parts.append("最近我经常选择%s，这说明它符合我当前的生活节奏" % _activity_label(dominant_activity))
	if player_mentions > 0:
		parts.append("玩家最近多次参与了我的生活，我会更优先留意对方")
	if not state.get("beliefs", {}).is_empty():
		parts.append("我也在观察同伴的意图，但这些判断仍可能出错")
	if parts.is_empty():
		parts.append("最近的经历还没有形成稳定模式，我可以继续观察")
	parts.append("我目前整体感到%s" % _mood_label(mood))
	var reflection := "；".join(parts) + "。"
	MemorySystem.add_reflection_for_agent(agent_id, reflection)
	_add_private_thought(agent_id, "我整理了近期经历，形成了一条新的长期反思。")


func _shift_mood(agent_id: String, valence_delta: float, arousal_delta: float) -> void:
	var mood: Dictionary = _ensure_state(agent_id)["mood"]
	mood["valence"] = clampf(float(mood.get("valence", 0.0)) + valence_delta, -1.0, 1.0)
	mood["arousal"] = clampf(float(mood.get("arousal", 0.4)) + arousal_delta, 0.0, 1.0)


func _add_private_thought(agent_id: String, content: String) -> void:
	var thoughts: Array = _ensure_state(agent_id)["private_thoughts"]
	thoughts.append({"timestamp": Time.get_unix_time_from_system(), "content": content})
	while thoughts.size() > MAX_PRIVATE_THOUGHTS:
		thoughts.pop_front()


func _ensure_state(agent_id: String) -> Dictionary:
	var normalized := agent_id if not agent_id.is_empty() else "main_agent"
	if not _states.has(normalized):
		var baseline: Dictionary = _profile(normalized).get("baseline_mood", {})
		_states[normalized] = {
			"mood": {
				"valence": float(baseline.get("valence", 0.0)),
				"arousal": float(baseline.get("arousal", 0.4)),
			},
			"attention": "",
			"intention": "",
			"beliefs": {},
			"recent_activities": [],
			"private_thoughts": [],
			"daily_plan": {},
		}
	return _states[normalized]


func _refresh_daily_plan(agent_id: String) -> void:
	var state := _ensure_state(agent_id)
	var current_day := WorldSimulator.day_number
	var current_period := _time_period_key()
	var existing: Dictionary = state.get("daily_plan", {})
	if int(existing.get("day", -1)) == current_day and String(existing.get("period", "")) == current_period:
		return
	var profile := _profile(agent_id)
	var weights: Dictionary = profile.get("daily_rhythm", {}).get(current_period, {}).duplicate(true)
	var ranked := []
	for activity_id in weights:
		ranked.append({"activity_id": String(activity_id), "weight": float(weights[activity_id])})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary): return float(a["weight"]) > float(b["weight"]))
	var priorities: Array[String] = []
	for item in ranked.slice(0, mini(3, ranked.size())):
		priorities.append(String(item["activity_id"]))
	state["daily_plan"] = {
		"day": current_day,
		"period": current_period,
		"priorities": priorities,
		"completed": existing.get("completed", []) if int(existing.get("day", -1)) == current_day else [],
	}


func _time_period_key() -> String:
	match WorldSimulator.time_of_day:
		AffordanceTypes.TimeOfDay.MORNING: return "morning"
		AffordanceTypes.TimeOfDay.NOON: return "noon"
		AffordanceTypes.TimeOfDay.AFTERNOON: return "afternoon"
		AffordanceTypes.TimeOfDay.EVENING: return "evening"
		AffordanceTypes.TimeOfDay.NIGHT: return "night"
	return "morning"


func _profile(agent_id: String) -> Dictionary:
	return _profiles.get(agent_id, _profiles.get("main_agent", {}))


func _value(values: Dictionary, key: String) -> float:
	return clampf(float(values.get(key, 0.5)), 0.0, 1.0)


func _mood_label(mood: Dictionary) -> String:
	var valence := float(mood.get("valence", 0.0))
	var arousal := float(mood.get("arousal", 0.4))
	if valence > 0.35 and arousal > 0.55:
		return "cheerful"
	if valence > 0.2:
		return "content"
	if valence < -0.25 and arousal > 0.55:
		return "tense"
	if valence < -0.2:
		return "low"
	if arousal < 0.28:
		return "calm"
	return "neutral"


func _estimate_sentiment(text: String) -> float:
	var value := 0.0
	for word in ["喜欢", "谢谢", "开心", "可爱", "真棒", "一起", "朋友"]:
		if word in text:
			value += 0.2
	for word in ["讨厌", "生气", "笨", "走开", "不要", "难过"]:
		if word in text:
			value -= 0.25
	return clampf(value, -1.0, 1.0)


func _inferred_intent(activity_id: String) -> String:
	match activity_id:
		"plant_care": return "希望小绿恢复健康"
		"read_book": return "希望获得安静和新信息"
		"rest_on_sofa": return "希望恢复精力和舒适感"
		"wander_room": return "希望活动身体并观察环境"
	return "正在完成自己的短期目标"


func _activity_label(activity_id: String) -> String:
	match activity_id:
		"plant_care": return "照顾小绿"
		"read_book": return "读书"
		"rest_on_sofa": return "在沙发休息"
		"wander_room": return "在房间走走"
	return activity_id


func _turn_agent_toward_camera(agent_id: String) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera:
		_turn_agent_toward_position(agent_id, camera.global_position)


func _turn_agent_toward_agent(observer_id: String, target_id: String) -> void:
	var target := _find_agent(target_id)
	if target:
		_turn_agent_toward_position(observer_id, target.global_position)


func _turn_agent_toward_position(agent_id: String, position: Vector3) -> void:
	var agent := _find_agent(agent_id)
	if agent and agent.has_method("turn_towards_world_position"):
		agent.turn_towards_world_position(position, 0.32)


func _find_agent(agent_id: String) -> Node3D:
	for node in get_tree().get_nodes_in_group("agents"):
		if String(node.get("agent_name")) == agent_id and node is Node3D:
			return node
	return null


func _load_profiles() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if parsed is Dictionary:
		_profiles = parsed.get("agents", {})
