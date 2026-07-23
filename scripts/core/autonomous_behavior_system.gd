extends Node

const PLAYER_GRACE_SECONDS := 12.0
const ROUTINE_COOLDOWN_SECONDS := 45.0
const DRY_STATES := ["需要浇水", "严重缺水", "枯萎"]

var _active_agent_id := ""
var _last_player_input_msec := -12000
var _last_routine_msec := -45000
var _evaluation_pending := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	MessageBus.world_state_changed.connect(_on_world_state_changed)
	MessageBus.player_message_received.connect(_on_player_message)
	MessageBus.action_queue_completed.connect(_on_action_queue_completed)
	call_deferred("_schedule_initial_evaluation")


func evaluate_now() -> bool:
	if not _can_start_routine():
		return false
	var plant = SemanticWorld.get_object("plant")
	if not plant or String(plant.state) not in DRY_STATES:
		return false
	var agent := _choose_idle_agent()
	if not agent:
		return false
	return _start_water_and_rest_routine(agent)


func get_active_agent_id() -> String:
	return _active_agent_id


func _schedule_initial_evaluation() -> void:
	await get_tree().create_timer(3.0).timeout
	evaluate_now()


func _on_world_state_changed(change_type: String, data: Dictionary) -> void:
	if change_type not in ["object_properties_changed", "save_loaded"]:
		return
	if change_type == "object_properties_changed" and String(data.get("object_id", "")) != "plant":
		return
	if _evaluation_pending:
		return
	_evaluation_pending = true
	get_tree().create_timer(1.5).timeout.connect(func():
		_evaluation_pending = false
		evaluate_now()
	)


func _on_player_message(_text: String, _is_command: bool) -> void:
	_last_player_input_msec = Time.get_ticks_msec()
	# Stop the current autonomous queue immediately; CognitiveCycle can then replace it
	# with the player's response without waiting for a long navigation task to finish.
	var interrupted_agent_id := _active_agent_id
	_active_agent_id = ""
	if not interrupted_agent_id.is_empty():
		MessageBus.emit_actions.emit(interrupted_agent_id, [])


func _on_action_queue_completed(agent_id: String) -> void:
	if agent_id != _active_agent_id:
		return
	MemorySystem.add_episode_for_agent(agent_id, "发现小绿缺水后主动浇了水，并去沙发休息。", 6.0)
	_emit_visible_social_line(agent_id, "小绿喝饱水啦，我也休息一会儿。", "happy")
	_active_agent_id = ""
	_last_routine_msec = Time.get_ticks_msec()


func _can_start_routine() -> bool:
	if not _active_agent_id.is_empty():
		return false
	var now := Time.get_ticks_msec()
	if now - _last_player_input_msec < int(PLAYER_GRACE_SECONDS * 1000.0):
		return false
	if now - _last_routine_msec < int(ROUTINE_COOLDOWN_SECONDS * 1000.0):
		return false
	if has_node("/root/CognitiveCycle") and bool(get_node("/root/CognitiveCycle").get("is_processing")):
		return false
	return true


func _choose_idle_agent() -> Node:
	var candidates := get_tree().get_nodes_in_group("agents")
	candidates.sort_custom(func(a: Node, b: Node):
		return String(a.get("agent_name")) == "main_agent" and String(b.get("agent_name")) != "main_agent"
	)
	for agent in candidates:
		if String(agent.get("current_activity")) == "idle":
			return agent
	return null


func _start_water_and_rest_routine(agent: Node) -> bool:
	var planner := GOAPPlanner.new()
	add_child(planner)
	var actions := planner.plan("water_plant")
	actions.append_array(planner.plan("rest_on_sofa"))
	planner.queue_free()
	if actions.size() < 5:
		return false
	# Autonomous rest should be visible without blocking the character for too long.
	var final_action = actions[-1]
	final_action.params["duration"] = 2.0
	_active_agent_id = String(agent.get("agent_name"))
	_last_routine_msec = Time.get_ticks_msec()
	MemorySystem.add_episode_for_agent(_active_agent_id, "注意到小绿缺水，决定先去浇水再到沙发休息。", 5.0)
	_emit_visible_social_line(_active_agent_id, "小绿看起来有点渴，我去给它浇水。", "neutral")
	_emit_companion_acknowledgement(_active_agent_id)
	MessageBus.emit_actions.emit(_active_agent_id, actions)
	return true


func _emit_companion_acknowledgement(actor_id: String) -> void:
	for node in get_tree().get_nodes_in_group("agents"):
		var listener_id := String(node.get("agent_name"))
		if listener_id == actor_id or String(node.get("current_activity")) != "idle":
			continue
		MemorySystem.add_episode_for_agent(listener_id, "%s主动去照顾缺水的小绿。" % CodifiedProfile.get_agent_display_name(actor_id), 4.0)
		MemorySystem.update_relationship_for_agent(listener_id, actor_id, "respect", 0.02)
		_emit_visible_social_line(listener_id, "好呀，浇完水记得休息一下。", "happy")
		break


func _emit_visible_social_line(agent_id: String, text: String, emotion: String) -> void:
	MessageBus.agent_show_bubble.emit(agent_id, text, emotion, 4.0)
	MessageBus.ui_add_chat_entry.emit(agent_id, text, false)
	MessageBus.performance_cue.emit("talk", {
		"agent_id": agent_id,
		"emotion": emotion,
		"source": "autonomous_routine",
	})
	if emotion == "happy":
		MessageBus.performance_cue.emit("happy", {
			"agent_id": agent_id,
			"source": "autonomous_routine",
		})
	MessageBus.tts_speech_requested.emit(text, {
		"agent_id": agent_id,
		"emotion": emotion,
		"source": "autonomous_routine",
	})
