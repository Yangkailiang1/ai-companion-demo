# Roadmap: C4.5, C9.1, C9.3
# Responsibility: 结算自主活动的成功或失败并释放资源；不选择或执行活动。
# Collaborators: AutonomousBehaviorSystem, MemorySystem, MessageBus
# Tests: scripts/debug/action_failure_contract_check.gd, scripts/debug/autonomous_life_check.gd

class_name AutonomousActivityOutcome
extends RefCounted

const POST_ACTIVITY_QUIET_SECONDS := 5.0


## [C9.1][C9.3] 结算成功活动，写入完成记忆、社交反馈并释放资源。
func complete(host: Node, agent_id: String) -> void:
	if not host._active_activities.has(agent_id):
		if host._suspended_activities.has(agent_id):
			host._schedule_resume_after_player(agent_id)
		return
	var activity: Dictionary = host._active_activities[agent_id]
	var definition: Dictionary = activity.get("definition", {})
	MemorySystem.add_episode_for_agent(
		agent_id,
		String(definition.get("completion_memory", "完成了一项日常活动。")),
		5.0,
	)
	var completion_line := String(definition.get("completion_line", ""))
	if not completion_line.is_empty():
		host._emit_visible_social_line(
			agent_id, completion_line, String(definition.get("emotion", "neutral"))
		)
	if String(activity.get("activity_id", "")) == "plant_care":
		_emit_companion_observation(host, agent_id)
	MessageBus.agent_activity_completed.emit(agent_id, String(activity.get("activity_id", "")), {
		"duration_seconds": _duration_seconds(activity),
	})
	host._release_activity(agent_id)
	host._agent_available_after_msec[agent_id] = (
		Time.get_ticks_msec() + int(POST_ACTIVITY_QUIET_SECONDS * 1000.0)
	)
	host._diagnostics["status"] = "activity_completed"
	host._diagnostics["completed"] = {
		"agent_id": agent_id,
		"activity_id": activity.get("activity_id", ""),
	}
	if host._scheduler_enabled:
		host.call_deferred("evaluate_now")


## [C4.5][C9.3] 结算失败活动，只写失败记忆/中断事件并释放资源。
func fail(host: Node, agent_id: String, reason: String, context: Dictionary) -> void:
	if not host._active_activities.has(agent_id):
		return
	var activity: Dictionary = host._active_activities[agent_id]
	var activity_id := String(activity.get("activity_id", ""))
	MemorySystem.add_episode_for_agent(
		agent_id,
		"尝试进行%s，但因为%s没有完成。" % [host._activity_label(activity), reason],
		4.0,
	)
	MessageBus.agent_activity_interrupted.emit(agent_id, activity_id, reason)
	host._release_activity(agent_id)
	host._agent_available_after_msec[agent_id] = Time.get_ticks_msec() + 1500
	host._diagnostics["status"] = "activity_failed"
	host._diagnostics["failed"] = {
		"agent_id": agent_id,
		"activity_id": activity_id,
		"reason": reason,
		"context": context.duplicate(true),
	}
	if host._scheduler_enabled:
		host.call_deferred("evaluate_now")


## [C9.1] 返回活动已运行秒数；纯读取。
func _duration_seconds(activity: Dictionary) -> float:
	var started_at := int(activity.get("started_at_msec", Time.get_ticks_msec()))
	return float(Time.get_ticks_msec() - started_at) / 1000.0


## [C9.1][C9.4] 让一名空闲同伴观察照料植物的结果并形成关系记忆。
func _emit_companion_observation(host: Node, actor_id: String) -> void:
	for node in host.get_tree().get_nodes_in_group("agents"):
		var listener_id := String(node.get("agent_name"))
		if listener_id == actor_id or String(node.get("current_activity")) != "idle":
			continue
		MemorySystem.add_episode_for_agent(
			listener_id,
			"%s主动去照顾缺水的小绿。" % CodifiedProfile.get_agent_display_name(actor_id),
			4.0,
		)
		MemorySystem.update_relationship_for_agent(listener_id, actor_id, "respect", 0.02)
		host._emit_visible_social_line(listener_id, "小绿精神多了，辛苦啦。", "happy")
		return
