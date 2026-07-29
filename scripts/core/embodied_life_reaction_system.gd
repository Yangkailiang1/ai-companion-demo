# Roadmap: C9.5, S3.3
# Responsibility: Turn meaningful physical-world changes into one nearby
# character reaction. Does not detect physics changes or run LLM dialogue.
# Collaborators: DynamicPropObserver, MemorySystem, MessageBus, ActionExecutor
# Tests: scripts/debug/embodied_life_reaction_check.gd

extends Node

const REACTION_COOLDOWN_SECONDS := 8.0

var _last_reaction_msec := -8000


## [C9.5] 订阅具身世界事件；演出模式下保持导演独占。
func _ready() -> void:
	MessageBus.world_state_changed.connect(_on_world_state_changed)


## [C9.5][S3.3] 选择最近空闲角色，把感知、记忆、表情和整理动作连成闭环。
func _on_world_state_changed(change_type: String, data: Dictionary) -> void:
	if change_type != "dynamic_prop_displaced" or _performance_mode_active():
		return
	var now := Time.get_ticks_msec()
	if now - _last_reaction_msec < int(REACTION_COOLDOWN_SECONDS * 1000.0):
		return
	var object_id := String(data.get("object_id", ""))
	var actor := _nearest_idle_agent(data.get("position", Vector3.ZERO))
	if object_id.is_empty() or actor == null:
		return
	_last_reaction_msec = now
	var agent_id := String(actor.get("agent_name"))
	var display_name := CodifiedProfile.get_agent_display_name(agent_id)
	MemorySystem.add_episode_for_agent(
		agent_id,
		"看到玩家把%s碰离了原位，决定过去整理。" % _object_name(object_id),
		4.0,
	)
	MessageBus.expression_cue.emit("surprised", 0.55, {
		"agent_id": agent_id,
		"source": "embodied_world_reaction",
	})
	MessageBus.emit_actions.emit(agent_id, _build_tidy_actions(
		object_id, "%s：哎呀，它跑到那边去了，我来放好。" % display_name
	))


## [C9.5] 构造可验收的具身动作序列：观察、说话、接近、拿起、放下。
func _build_tidy_actions(object_id: String, line: String) -> Array:
	return [
		AffordanceTypes.PrimitiveAction.new(
			AffordanceTypes.Primitive.LOOK_AT, {"target": object_id}
		),
		AffordanceTypes.PrimitiveAction.new(
			AffordanceTypes.Primitive.SPEAK, {"text": line, "tone": "surprised"}
		),
		AffordanceTypes.PrimitiveAction.new(
			AffordanceTypes.Primitive.NAVIGATE, {"target": object_id}
		),
		AffordanceTypes.PrimitiveAction.new(
			AffordanceTypes.Primitive.PICK_UP, {"object": object_id}
		),
		AffordanceTypes.PrimitiveAction.new(
			AffordanceTypes.Primitive.PUT_DOWN, {"object": object_id}
		),
	]


## [C9.5] 返回离事件最近且没有执行活动/动作队列的角色。
func _nearest_idle_agent(position_value: Variant) -> Node3D:
	var position := position_value as Vector3 if position_value is Vector3 else Vector3.ZERO
	var selected: Node3D
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("agents"):
		if not node is Node3D or String(node.get("current_activity")) != "idle":
			continue
		var executor := node.get_node_or_null("ActionExecutor") as ActionExecutor
		if executor != null and executor.is_executing:
			continue
		var distance := (node as Node3D).global_position.distance_to(position)
		if distance < best_distance:
			selected = node as Node3D
			best_distance = distance
	return selected


## [C9.5] 获取面向玩家的物体名；缺失时回退稳定 ID。
func _object_name(object_id: String) -> String:
	var object = SemanticWorld.get_object(object_id)
	return String(object.name) if object != null else object_id


## [D3][C9.5] 演出期间不插入自由生活反应。
func _performance_mode_active() -> bool:
	return (
		has_node("/root/ExperienceModeManager")
		and ExperienceModeManager.is_performance_mode()
	)
