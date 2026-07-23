# social_system.gd — Minimal multi-agent social glue.
# Records overheard speech into each agent's own memory and occasionally lets
# another idle agent respond. It is intentionally conservative to avoid ping-pong.

extends Node

const SOCIAL_REPLY_COOLDOWN := 55.0
const SOCIAL_REPLY_PROBABILITY := 0.35

var _last_reply_by_pair: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if MessageBus.has_signal("agent_spoke"):
		MessageBus.agent_spoke.connect(_on_agent_spoke)


func _on_agent_spoke(speaker_id: String, text: String, emotion: String) -> void:
	if text.strip_edges().is_empty():
		return
	for node in get_tree().get_nodes_in_group("agents"):
		if node.get("agent_name") == null:
			continue
		var listener_id := String(node.get("agent_name"))
		if listener_id == speaker_id:
			continue
		MemorySystem.add_episode_for_agent(listener_id, "%s说：%s" % [CodifiedProfile.get_agent_display_name(speaker_id), text], 3.0)
		MemorySystem.update_relationship_for_agent(listener_id, speaker_id, "familiarity", 0.03)
		_maybe_trigger_social_reply(listener_id, speaker_id, text)


func _maybe_trigger_social_reply(listener_id: String, speaker_id: String, text: String) -> void:
	if randf() > SOCIAL_REPLY_PROBABILITY:
		return
	var pair_key := "%s<-:%s" % [listener_id, speaker_id]
	var now := Time.get_unix_time_from_system()
	if now - float(_last_reply_by_pair.get(pair_key, 0.0)) < SOCIAL_REPLY_COOLDOWN:
		return
	if _is_agent_busy(listener_id):
		return
	_last_reply_by_pair[pair_key] = now
	var prompt := "%s刚才说：“%s”。你可以自然回应一句，也可以做一个轻微动作；不要重复对方原话。" % [
		CodifiedProfile.get_agent_display_name(speaker_id),
		text.left(80),
	]
	MessageBus.agent_trigger_cycle.emit(listener_id, AffordanceTypes.TriggerSource.PLAYER_INPUT, {
		"text": prompt,
		"is_command": false,
		"social_from": speaker_id,
	})


func _is_agent_busy(agent_id: String) -> bool:
	for node in get_tree().get_nodes_in_group("agents"):
		if node.get("agent_name") != null and String(node.get("agent_name")) == agent_id:
			return String(node.get("current_activity")) != "idle"
	return false
