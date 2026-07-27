extends Node

const CONFIG_PATH := "res://data/autonomous_life_config.json"
const PLAYER_GRACE_SECONDS := 10.0
const DEFAULT_EVALUATION_INTERVAL := 6.0
const MICRO_BEHAVIOR_COOLDOWN_SECONDS := 14.0
const GLOBAL_ACTIVITY_START_GAP_SECONDS := 2.0
const POST_ACTIVITY_QUIET_SECONDS := 5.0
const SUSPENDED_ACTIVITY_MAX_AGE_SECONDS := 90.0
const DRY_STATES := ["需要浇水", "严重缺水", "枯萎"]

var _config: Dictionary = {}
var _activities: Array = []
var _active_activities: Dictionary = {}
var _suspended_activities: Dictionary = {}
var _resource_owners: Dictionary = {}
var _activity_last_started: Dictionary = {}
var _agent_available_after_msec: Dictionary = {}
var _micro_last_played: Dictionary = {}
var _micro_indices: Dictionary = {}
var _last_player_input_msec := -10000
var _last_global_start_msec := -2000
var _evaluation_pending := false
var _player_input_epoch := 0
var _resume_scheduled_epoch: Dictionary = {}
var _diagnostics: Dictionary = {
	"status": "initializing",
	"candidates": [],
	"selected": {},
}
var _scheduler_enabled := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_config()
	MessageBus.world_state_changed.connect(_on_world_state_changed)
	MessageBus.player_message_received.connect(_on_player_message)
	MessageBus.action_queue_completed.connect(_on_action_queue_completed)
	call_deferred("_scheduler_loop")


func evaluate_now() -> bool:
	if not _can_evaluate():
		return false
	var candidates := _score_candidates()
	_diagnostics = {
		"status": "no_candidate",
		"evaluated_at_msec": Time.get_ticks_msec(),
		"candidates": candidates.duplicate(true),
		"selected": {},
	}
	for candidate in candidates:
		if float(candidate.get("score", 0.0)) < float(candidate.get("minimum_score", 0.0)):
			continue
		if _start_activity(candidate):
			_diagnostics["status"] = "activity_started"
			_diagnostics["selected"] = candidate.duplicate(true)
			return true
	_try_micro_behavior()
	return false


func get_active_agent_id() -> String:
	if _active_activities.has("main_agent"):
		return "main_agent"
	if not _active_activities.is_empty():
		return String(_active_activities.keys()[0])
	return ""


func get_active_activity(agent_id: String) -> String:
	return String(_active_activities.get(agent_id, {}).get("activity_id", ""))


func get_suspended_activity(agent_id: String) -> String:
	return String(_suspended_activities.get(agent_id, {}).get("activity_id", ""))


func get_diagnostics() -> Dictionary:
	return _diagnostics.duplicate(true)


func set_scheduler_enabled(enabled: bool) -> void:
	_scheduler_enabled = enabled


func _load_config() -> void:
	_config = _read_json(CONFIG_PATH)
	_activities = _config.get("activities", [])
	if _activities.is_empty():
		push_error("AutonomousBehaviorSystem: no activities in %s" % CONFIG_PATH)


func _scheduler_loop() -> void:
	await get_tree().create_timer(3.0).timeout
	while is_inside_tree():
		if _scheduler_enabled:
			evaluate_now()
		var interval := float(_config.get("evaluation_interval_seconds", DEFAULT_EVALUATION_INTERVAL))
		await get_tree().create_timer(maxf(interval, 1.0)).timeout


func _on_world_state_changed(change_type: String, data: Dictionary) -> void:
	if change_type not in ["object_properties_changed", "save_loaded", "time_of_day_changed"]:
		return
	if change_type == "object_properties_changed" and String(data.get("object_id", "")) != "plant":
		return
	if _evaluation_pending:
		return
	_evaluation_pending = true
	get_tree().create_timer(1.0).timeout.connect(func():
		_evaluation_pending = false
		if _scheduler_enabled:
			evaluate_now()
	)


func _on_player_message(_text: String, _is_command: bool) -> void:
	_last_player_input_msec = Time.get_ticks_msec()
	_player_input_epoch += 1
	var interrupted_ids := _active_activities.keys()
	for agent_id in interrupted_ids:
		var activity: Dictionary = _active_activities.get(agent_id, {})
		var activity_id := String(activity.get("activity_id", ""))
		activity["suspended_at_msec"] = Time.get_ticks_msec()
		activity["player_epoch"] = _player_input_epoch
		_suspended_activities[String(agent_id)] = activity.duplicate(true)
		MemorySystem.add_episode_for_agent(String(agent_id), "玩家呼唤时暂停了%s。" % _activity_label(activity), 3.0)
		MessageBus.agent_activity_interrupted.emit(String(agent_id), activity_id, "player")
		_release_activity(String(agent_id))
		MessageBus.emit_actions.emit(String(agent_id), [])
	_diagnostics["status"] = "interrupted_by_player"
	_diagnostics["selected"] = {}


func _on_action_queue_completed(agent_id: String) -> void:
	if not _active_activities.has(agent_id):
		if _suspended_activities.has(agent_id):
			_schedule_resume_after_player(agent_id)
		return
	var activity: Dictionary = _active_activities[agent_id]
	var definition: Dictionary = activity.get("definition", {})
	var completion_memory := String(definition.get("completion_memory", "完成了一项日常活动。"))
	MemorySystem.add_episode_for_agent(agent_id, completion_memory, 5.0)
	var completion_line := String(definition.get("completion_line", ""))
	if not completion_line.is_empty():
		_emit_visible_social_line(agent_id, completion_line, String(definition.get("emotion", "neutral")))
	if String(activity.get("activity_id", "")) == "plant_care":
		_emit_companion_observation(agent_id)
	MessageBus.agent_activity_completed.emit(agent_id, String(activity.get("activity_id", "")), {
		"duration_seconds": float(Time.get_ticks_msec() - int(activity.get("started_at_msec", Time.get_ticks_msec()))) / 1000.0,
	})
	_release_activity(agent_id)
	_agent_available_after_msec[agent_id] = Time.get_ticks_msec() + int(POST_ACTIVITY_QUIET_SECONDS * 1000.0)
	_diagnostics["status"] = "activity_completed"
	_diagnostics["completed"] = {
		"agent_id": agent_id,
		"activity_id": activity.get("activity_id", ""),
	}
	if _scheduler_enabled:
		call_deferred("evaluate_now")


func resume_suspended_now(agent_id: String) -> bool:
	if not _suspended_activities.has(agent_id):
		return false
	var suspended: Dictionary = _suspended_activities[agent_id]
	var age_msec := Time.get_ticks_msec() - int(suspended.get("suspended_at_msec", 0))
	if age_msec > int(SUSPENDED_ACTIVITY_MAX_AGE_SECONDS * 1000.0):
		_abandon_suspended(agent_id, "等待时间太久")
		return false
	if Time.get_ticks_msec() - _last_player_input_msec < int(PLAYER_GRACE_SECONDS * 1000.0):
		return false
	if has_node("/root/CognitiveCycle") and bool(get_node("/root/CognitiveCycle").get("is_processing")):
		return false
	var agent := _find_agent(agent_id)
	if not agent or String(agent.get("current_activity")) != "idle":
		return false
	var definition: Dictionary = suspended.get("definition", {})
	var condition_result := _evaluate_condition(String(definition.get("condition", "")))
	if not bool(condition_result.get("available", true)):
		_abandon_suspended(agent_id, "环境已经变化")
		return false
	if not _resources_available(definition.get("resources", [])):
		return false
	var candidate: Dictionary = suspended.get("candidate", {}).duplicate(true)
	if candidate.is_empty():
		candidate = {
			"agent_id": agent_id,
			"activity_id": suspended.get("activity_id", ""),
			"score": 1.0,
			"definition": definition,
		}
	candidate["resumed"] = true
	_suspended_activities.erase(agent_id)
	var started := _start_activity(candidate)
	if started:
		_diagnostics["status"] = "activity_resumed"
		_diagnostics["selected"] = candidate.duplicate(true)
	return started


func _schedule_resume_after_player(agent_id: String) -> void:
	var epoch := _player_input_epoch
	if int(_resume_scheduled_epoch.get(agent_id, -1)) == epoch:
		return
	_resume_scheduled_epoch[agent_id] = epoch
	_attempt_resume_after_player(agent_id, epoch)


func _attempt_resume_after_player(agent_id: String, epoch: int) -> void:
	var elapsed := float(Time.get_ticks_msec() - _last_player_input_msec) / 1000.0
	await get_tree().create_timer(maxf(PLAYER_GRACE_SECONDS - elapsed + 0.2, 0.2)).timeout
	if epoch != _player_input_epoch or not _suspended_activities.has(agent_id):
		return
	for _attempt in range(3):
		if resume_suspended_now(agent_id):
			return
		if not _suspended_activities.has(agent_id):
			return
		await get_tree().create_timer(2.0).timeout


func _abandon_suspended(agent_id: String, reason: String) -> void:
	var suspended: Dictionary = _suspended_activities.get(agent_id, {})
	if suspended.is_empty():
		return
	MemorySystem.add_episode_for_agent(
		agent_id,
		"没有恢复%s，因为%s。" % [_activity_label(suspended), reason],
		3.0
	)
	_suspended_activities.erase(agent_id)


func _can_evaluate() -> bool:
	var now := Time.get_ticks_msec()
	if now - _last_player_input_msec < int(PLAYER_GRACE_SECONDS * 1000.0):
		_diagnostics["status"] = "player_grace"
		return false
	if now - _last_global_start_msec < int(GLOBAL_ACTIVITY_START_GAP_SECONDS * 1000.0):
		return false
	if has_node("/root/CognitiveCycle") and bool(get_node("/root/CognitiveCycle").get("is_processing")):
		_diagnostics["status"] = "cognitive_cycle_busy"
		return false
	return true


func _score_candidates() -> Array:
	var candidates: Array = []
	for agent in get_tree().get_nodes_in_group("agents"):
		var agent_id := String(agent.get("agent_name"))
		if agent_id.is_empty() or _active_activities.has(agent_id) or _suspended_activities.has(agent_id):
			continue
		if Time.get_ticks_msec() < int(_agent_available_after_msec.get(agent_id, 0)):
			continue
		if String(agent.get("current_activity")) != "idle":
			continue
		for definition_value in _activities:
			var definition: Dictionary = definition_value
			var candidate := _score_activity(agent, agent_id, definition)
			if not candidate.is_empty():
				candidates.append(candidate)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary):
		var score_delta := float(a.get("score", 0.0)) - float(b.get("score", 0.0))
		if absf(score_delta) > 0.0001:
			return score_delta > 0.0
		return String(a.get("agent_id", "")) < String(b.get("agent_id", ""))
	)
	return candidates


func _score_activity(agent: Node, agent_id: String, definition: Dictionary) -> Dictionary:
	var activity_id := String(definition.get("id", ""))
	if activity_id.is_empty() or not _resources_available(definition.get("resources", [])):
		return {}
	var cooldown_seconds := float(definition.get("cooldown_seconds", 30.0))
	var cooldown_key := "%s:%s" % [agent_id, activity_id]
	var last_started := int(_activity_last_started.get(cooldown_key, -int(cooldown_seconds * 1000.0)))
	if Time.get_ticks_msec() - last_started < int(cooldown_seconds * 1000.0):
		return {}

	var condition_result := _evaluate_condition(String(definition.get("condition", "")))
	if not bool(condition_result.get("available", true)):
		return {}
	var preference := _agent_preference(agent_id, activity_id)
	var psyche_modifier := AgentPsycheSystem.get_utility_modifier(agent_id, activity_id)
	var schedule_modifier := AgentPsycheSystem.get_schedule_modifier(agent_id, activity_id)
	var base_score := float(definition.get("base_score", 0.0))
	var need_score := _need_deficit(agent_id, String(definition.get("need", ""))) * float(definition.get("need_weight", 0.0))
	var condition_score := float(condition_result.get("strength", 0.0)) * float(definition.get("condition_weight", 0.0))
	var distance_score := _distance_bonus(agent, String(definition.get("focus_target", ""))) * 0.06
	var score := (base_score + need_score + condition_score + distance_score) * preference * psyche_modifier * schedule_modifier
	return {
		"agent_id": agent_id,
		"activity_id": activity_id,
		"score": snappedf(score, 0.001),
		"minimum_score": float(definition.get("minimum_score", 0.0)),
		"preference": preference,
		"psyche_modifier": snappedf(psyche_modifier, 0.001),
		"psyche_reason": AgentPsycheSystem.get_utility_reason(agent_id, activity_id),
		"schedule_modifier": snappedf(schedule_modifier, 0.001),
		"daily_plan": AgentPsycheSystem.get_daily_plan(agent_id),
		"base_score": base_score,
		"need_score": snappedf(need_score, 0.001),
		"condition_score": snappedf(condition_score, 0.001),
		"distance_score": snappedf(distance_score, 0.001),
		"definition": definition,
	}


func _evaluate_condition(condition: String) -> Dictionary:
	if condition.is_empty():
		return {"available": true, "strength": 0.0}
	if condition == "plant_dry":
		var plant = SemanticWorld.get_object("plant")
		if not plant or String(plant.state) not in DRY_STATES:
			return {"available": false, "strength": 0.0}
		var moisture := float(plant.properties.get("moisture", 35.0))
		return {"available": true, "strength": clampf((35.0 - moisture) / 35.0, 0.35, 1.0)}
	return {"available": false, "strength": 0.0}


func _agent_preference(agent_id: String, activity_id: String) -> float:
	var agents: Dictionary = _config.get("agents", {})
	var profile: Dictionary = agents.get(agent_id, {})
	var preferences: Dictionary = profile.get("preferences", {})
	return clampf(float(preferences.get(activity_id, 1.0)), 0.1, 2.0)


func _need_deficit(agent_id: String, need_name: String) -> float:
	if need_name.is_empty():
		return 0.0
	var needs := WorldSimulator.get_needs_for_agent(agent_id)
	var value := 100.0
	match need_name:
		"hunger": value = needs.hunger
		"energy": value = needs.energy
		"social": value = needs.social
		"fun": value = needs.fun
		_: return 0.0
	return clampf((100.0 - value) / 100.0, 0.0, 1.0)


func _distance_bonus(agent: Node, target_id: String) -> float:
	if target_id.is_empty() or not agent is Node3D:
		return 0.0
	var object = SemanticWorld.get_object(target_id)
	if not object:
		return 0.0
	var distance: float = (agent as Node3D).global_position.distance_to(object.interaction_point)
	return clampf(1.0 - distance / 8.0, 0.0, 1.0)


func _resources_available(resources: Array) -> bool:
	for resource_id in resources:
		if _resource_owners.has(String(resource_id)):
			return false
	return true


func _start_activity(candidate: Dictionary) -> bool:
	var definition: Dictionary = candidate.get("definition", {})
	var agent_id := String(candidate.get("agent_id", ""))
	var actions: Array = []
	var focus_target := String(definition.get("focus_target", ""))
	if not focus_target.is_empty():
		actions.append(AffordanceTypes.PrimitiveAction.new(
			AffordanceTypes.Primitive.LOOK_AT,
			{"target": focus_target}
		))
	var planner := GOAPPlanner.new()
	add_child(planner)
	for goal in definition.get("goals", []):
		actions.append_array(planner.plan(String(goal)))
	planner.queue_free()
	if actions.is_empty():
		return false
	if String(candidate.get("activity_id", "")) == "plant_care":
		var final_action = actions[-1]
		if final_action.type == AffordanceTypes.Primitive.IDLE:
			final_action.params["duration"] = 2.0

	var resources: Array = definition.get("resources", []).duplicate()
	for resource_id in resources:
		_resource_owners[String(resource_id)] = agent_id
	var activity_id := String(candidate.get("activity_id", ""))
	_active_activities[agent_id] = {
		"activity_id": activity_id,
		"definition": definition,
		"resources": resources,
		"started_at_msec": Time.get_ticks_msec(),
		"candidate": candidate.duplicate(true),
	}
	_activity_last_started["%s:%s" % [agent_id, activity_id]] = Time.get_ticks_msec()
	_last_global_start_msec = Time.get_ticks_msec()
	MessageBus.agent_activity_started.emit(agent_id, activity_id, {
		"focus_target": focus_target,
		"score": candidate.get("score", 0.0),
		"psyche_reason": candidate.get("psyche_reason", ""),
		"resumed": bool(candidate.get("resumed", false)),
	})

	var start_memory := (
		"回应玩家后，决定恢复%s。" % _activity_label({"activity_id": activity_id})
		if bool(candidate.get("resumed", false))
		else String(definition.get("start_memory", "开始了一项日常活动。"))
	)
	MemorySystem.add_episode_for_agent(agent_id, start_memory, 4.0)
	MessageBus.performance_cue.emit("think", {
		"agent_id": agent_id,
		"source": "utility_ai_transition",
		"activity_id": activity_id,
	})
	var start_line := String(definition.get("start_line", ""))
	if not start_line.is_empty():
		_emit_visible_social_line(agent_id, start_line, String(definition.get("emotion", "neutral")))
	MessageBus.emit_actions.emit(agent_id, actions)
	return true


func _find_agent(agent_id: String) -> Node:
	for node in get_tree().get_nodes_in_group("agents"):
		if String(node.get("agent_name")) == agent_id:
			return node
	return null


func _release_activity(agent_id: String) -> void:
	var activity: Dictionary = _active_activities.get(agent_id, {})
	for resource_id in activity.get("resources", []):
		if String(_resource_owners.get(String(resource_id), "")) == agent_id:
			_resource_owners.erase(String(resource_id))
	_active_activities.erase(agent_id)


func _try_micro_behavior() -> void:
	var agents_config: Dictionary = _config.get("agents", {})
	for agent in get_tree().get_nodes_in_group("agents"):
		var agent_id := String(agent.get("agent_name"))
		if _active_activities.has(agent_id) or String(agent.get("current_activity")) != "idle":
			continue
		var now := Time.get_ticks_msec()
		var last_played := int(_micro_last_played.get(agent_id, -int(MICRO_BEHAVIOR_COOLDOWN_SECONDS * 1000.0)))
		if now - last_played < int(MICRO_BEHAVIOR_COOLDOWN_SECONDS * 1000.0):
			continue
		var behaviors: Array = agents_config.get(agent_id, {}).get("micro_behaviors", [])
		if behaviors.is_empty():
			continue
		var index := int(_micro_indices.get(agent_id, 0)) % behaviors.size()
		var behavior := String(behaviors[index])
		_micro_indices[agent_id] = index + 1
		_micro_last_played[agent_id] = now
		_perform_micro_behavior(agent, agent_id, behavior)
		_diagnostics["status"] = "micro_behavior"
		_diagnostics["micro_behavior"] = {"agent_id": agent_id, "id": behavior}
		return


func _perform_micro_behavior(agent: Node, agent_id: String, behavior: String) -> void:
	var target_id := ""
	var cue := "idle"
	match behavior:
		"look_plant": target_id = "plant"
		"look_book": target_id = "book"
		"look_tv": target_id = "tv"
		"look_window":
			target_id = ""
			cue = "think"
		"think": cue = "think"
	if not target_id.is_empty() and agent.has_method("look_at_target"):
		agent.look_at_target(target_id)
	MessageBus.performance_cue.emit(cue, {
		"agent_id": agent_id,
		"source": "autonomous_micro_behavior",
		"behavior": behavior,
	})


func _emit_companion_observation(actor_id: String) -> void:
	for node in get_tree().get_nodes_in_group("agents"):
		var listener_id := String(node.get("agent_name"))
		if listener_id == actor_id or String(node.get("current_activity")) != "idle":
			continue
		MemorySystem.add_episode_for_agent(
			listener_id,
			"%s主动去照顾缺水的小绿。" % CodifiedProfile.get_agent_display_name(actor_id),
			4.0
		)
		MemorySystem.update_relationship_for_agent(listener_id, actor_id, "respect", 0.02)
		_emit_visible_social_line(listener_id, "小绿精神多了，辛苦啦。", "happy")
		break


func _emit_visible_social_line(agent_id: String, text: String, emotion: String) -> void:
	MessageBus.agent_show_bubble.emit(agent_id, text, emotion, 4.0)
	MessageBus.ui_add_chat_entry.emit(agent_id, text, false)
	MessageBus.performance_cue.emit("talk", {
		"agent_id": agent_id,
		"emotion": emotion,
		"source": "autonomous_life",
	})
	if emotion == "happy":
		MessageBus.performance_cue.emit("happy", {
			"agent_id": agent_id,
			"source": "autonomous_life",
		})
	MessageBus.tts_speech_requested.emit(text, {
		"agent_id": agent_id,
		"emotion": emotion,
		"source": "autonomous_life",
	})


func _activity_label(activity: Dictionary) -> String:
	match String(activity.get("activity_id", "")):
		"plant_care": return "照顾植物的活动"
		"read_book": return "阅读"
		"rest_on_sofa": return "休息"
		"wander_room": return "散步"
	return "当前活动"


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
