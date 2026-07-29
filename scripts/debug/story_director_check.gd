# Headless acceptance for structured story validation and multi-Agent direction.
# Verifies: D1, D2, T4.5
# Covers: validation, movement, mutual gaze, cues, dialogue, autonomy lock,
# memory, cancellation and stale async-stack isolation.

extends SceneTree

const VALIDATOR_PATH := "res://scripts/directing/story_schema_validator.gd"
const MAIN_PATH := "WorldRoot/LivingRoom/Agent"
const JUE_PATH := "WorldRoot/LivingRoom/JueAgent"

var failed := false
var _performance_cues: Array[Dictionary] = []
var _expression_cues: Array[Dictionary] = []
var _chat_entries: Array[Dictionary] = []


## [D1][D2] 延迟启动完整的剧情导演合同测试。
func _init() -> void:
	call_deferred("_run")


## [D1][D2][T4.5] 实例化真实主场景并组合验证、演出和取消合同。
func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var world_loader := scene.get_node("WorldRoot")
	_assert(
		world_loader.switch_location("legacy") == "legacy",
		"story fixture could not select deterministic legacy room",
	)
	await process_frame
	await process_frame
	var director := root.get_node("StoryDirector")
	var autonomy := root.get_node("AutonomousBehaviorSystem")
	var memory := root.get_node("MemorySystem")
	var bus := root.get_node("MessageBus")
	var cognitive := root.get_node("CognitiveCycle")
	cognitive.llm_api_url = ""
	cognitive.llm_api_key = ""

	_test_schema_contract()
	await _test_full_performance(scene, director, autonomy, memory, bus)
	await _test_bundled_cozy_story(scene, director, autonomy, memory, bus)
	await _test_cancel_and_replay(director, autonomy, memory, bus)

	if not failed:
		print("STORY_DIRECTOR_CHECK_PASS contracts=4")
	autonomy.set_scheduler_enabled(false)
	scene.free()
	quit(1 if failed else 0)


## [D1] 验证非法角色、非 cast 角色、动作、路点、字段和对白类型均被拒绝。
func _test_schema_contract() -> void:
	var validator = load(VALIDATOR_PATH).new(["main_agent", "jue_agent", "future_chibi"])
	_assert(not validator.validate(_document(["ghost"], [{"actor": "ghost"}])), "unregistered cast accepted")
	_assert(not validator.validate(_document(
		["main_agent"], [{"actor": "jue_agent"}])), "actor outside document cast accepted")
	_assert(not validator.validate(_document(
		["main_agent"], [{"actor": "main_agent", "gesture": "fly"}])), "invalid gesture accepted")
	_assert(not validator.validate(_document(
		["main_agent"], [{"actor": "main_agent", "move_to": {"waypoint": "mars"}}])),
		"invalid waypoint accepted")
	var unknown_field := _document(["main_agent"], [{"actor": "main_agent"}])
	unknown_field["camera_hack"] = true
	_assert(not validator.validate(unknown_field), "unknown root field accepted")
	_assert(not validator.validate(_document(
		["main_agent"], [{"actor": "main_agent", "say": 42}])), "non-string dialogue accepted")
	_assert(not validator.validate(_document(
		["main_agent"], [{
			"actor": "main_agent",
			"interact": {"object": "tv", "verb": "water"},
		}])), "invalid object interaction accepted")
	var legal := _document(["main_agent", "future_chibi"], [
		{"actor": "future_chibi", "look_at_actor": "main_agent", "gesture": "wave",
			"interact": {"object": "tv", "verb": "turn_on"}},
	])
	_assert(validator.validate(legal), "registered future Q character was rejected")


## [D2][T4.5] 验证真实走位、互相注视、对白表现、自主锁和独立剧情记忆。
func _test_full_performance(
	scene: Node,
	director: Node,
	autonomy: Node,
	memory: Node,
	bus: Node
) -> void:
	var main: Node3D = scene.get_node(MAIN_PATH)
	var jue: Node3D = scene.get_node(JUE_PATH)
	var tv: Node = scene.get_node("WorldRoot/LivingRoom/TV")
	var semantic := root.get_node("SemanticWorld")
	semantic.update_object_state("tv", "关闭")
	autonomy.set_scheduler_enabled(true)
	_begin_capture(bus)
	var story := _full_performance_story()
	_assert(director.play_story_document(story) == 0, "full performance did not start")
	await process_frame
	_assert(not bool(autonomy.get("_scheduler_enabled")), "autonomy stayed enabled during story")
	await _wait_for_idle(director, 30000, "full performance timed out")
	_assert(bool(autonomy.get("_scheduler_enabled")), "autonomy was not restored after story")
	autonomy.set_scheduler_enabled(false)
	await create_timer(0.4).timeout
	_end_capture(bus)

	var diagnostics: Dictionary = director.get_diagnostics()
	_assert(
		String(diagnostics.last_error).is_empty(),
		"successful story retained an error: %s" % diagnostics.last_error
	)
	_verify_position(main, "perimeter_w", "main_agent")
	_verify_position(jue, "room_center", "jue_agent")
	_verify_facing(main, jue, "main_agent")
	_verify_facing(jue, main, "jue_agent")
	_assert(String(semantic.get_object("tv").state) == "播放温馨节目", "TV state did not change")
	_assert(tv.get_node("TVScreenGlow").visible, "TV screen feedback stayed hidden")
	_verify_performance_order()
	_assert(_contains_chat("我们开始吧"), "main dialogue was not routed")
	_assert(_contains_chat("我准备好了"), "Jue dialogue was not routed")
	_assert(_has_memory(memory, "main_agent", "v08_full_performance"), "main story memory missing")
	_assert(_has_memory(memory, "jue_agent", "v08_full_performance"), "Jue story memory missing")
	autonomy.set_scheduler_enabled(true)


## [D2][S3.2] 验证随项目发布的小剧场能完成双人入座、看电视和独立记忆。
func _test_bundled_cozy_story(
	scene: Node,
	director: Node,
	autonomy: Node,
	memory: Node,
	bus: Node
) -> void:
	# 本合同只验证内置演出内容；调度恢复已由上一合同覆盖。
	# 保持关闭可避免 3 秒调度 tick 恰好在导演结束帧抢走最终构图。
	autonomy.set_scheduler_enabled(false)
	_begin_capture(bus)
	_assert(director.play_story("cozy_evening") == 0, "bundled cozy story did not start")
	await _wait_for_idle(director, 45000, "bundled cozy story timed out")
	autonomy.set_scheduler_enabled(false)
	await create_timer(0.35).timeout
	_end_capture(bus)
	_assert(
		String(director.get_diagnostics().last_error).is_empty(),
		"bundled cozy story failed: %s" % director.get_diagnostics().last_error,
	)
	var main: Node3D = scene.get_node(MAIN_PATH)
	var jue: Node3D = scene.get_node(JUE_PATH)
	_verify_position(main, "sofa_seat_left", "main_agent cozy seat")
	_verify_position(jue, "sofa_seat_right", "jue_agent cozy seat")
	_verify_facing_object(main, "tv", "main_agent cozy gaze")
	_verify_facing_object(jue, "tv", "jue_agent cozy gaze")
	_assert(_has_performance_cue("main_agent", "sit"), "main sit cue missing")
	_assert(_has_performance_cue("jue_agent", "sit"), "Jue sit cue missing")
	_assert(_contains_chat("坐在一起"), "cozy closing dialogue missing")
	_assert(_has_memory(memory, "main_agent", "温馨的邀约"), "main cozy memory missing")
	_assert(_has_memory(memory, "jue_agent", "温馨的邀约"), "Jue cozy memory missing")


## [D2][T4.5] 验证取消立即停止旧异步栈，恢复调度，并允许安全重播。
func _test_cancel_and_replay(
	director: Node,
	autonomy: Node,
	memory: Node,
	bus: Node
) -> void:
	autonomy.set_scheduler_enabled(true)
	_begin_capture(bus)
	var cancelled := _document(["main_agent"], [
		{"actor": "main_agent", "say": "取消前台词", "pause_after": 2.0},
		{"actor": "main_agent", "say": "泄漏台词", "gesture": "wave", "pause_after": 1.0},
	], "v08_cancelled_memory")
	_assert(director.play_story_document(cancelled) == 0, "cancel story did not start")
	await process_frame
	await process_frame
	director.cancel_story("acceptance")
	var chat_count := _chat_entries.size()
	var cue_count := _performance_cues.size()
	await create_timer(0.45).timeout
	_assert(_chat_entries.size() == chat_count, "dialogue continued after cancellation")
	_assert(_performance_cues.size() == cue_count, "performance continued after cancellation")
	_assert(not _contains_chat("泄漏台词"), "stale beat leaked after cancellation")
	_assert(not _has_memory(memory, "main_agent", "v08_cancelled_memory"), "cancelled story wrote memory")
	_assert(bool(autonomy.get("_scheduler_enabled")), "autonomy was not restored after cancellation")
	_assert("cancelled" in String(director.get_diagnostics().last_error), "cancel reason was not retained")
	_end_capture(bus)
	await _replay_after_cancel(director, bus)


## [D2][T4.5] 取消后立即播放新故事，并确认旧 Beat 不会污染新 Run。
func _replay_after_cancel(director: Node, bus: Node) -> void:
	_begin_capture(bus)
	var replay := _document(["main_agent"], [
		{"actor": "main_agent", "say": "取消后的新故事", "gesture": "happy", "pause_after": 0.15},
	], "v08_replay")
	_assert(director.play_story_document(replay) == 0, "replay did not start")
	await _wait_for_idle(director, 10000, "replay timed out")
	await create_timer(0.45).timeout
	_end_capture(bus)
	_assert(_contains_chat("取消后的新故事"), "replay dialogue missing")
	_assert(not _contains_chat("泄漏台词"), "old run polluted replay")
	_assert(String(director.get_diagnostics().last_error).is_empty(), "replay retained stale error")


## [D2] 构造包含双角色走位、最终互相注视和表现层 Cue 的演出。
func _full_performance_story() -> Dictionary:
	return _document(["main_agent", "jue_agent"], [
		{"actor": "main_agent", "move_to": {"waypoint": "perimeter_w"}, "pause_after": 0.1},
		{"actor": "jue_agent", "move_to": {"waypoint": "room_center"}, "pause_after": 0.1},
		{"actor": "main_agent", "look_at_actor": "jue_agent", "gesture": "wave",
			"expression": "happy", "interact": {"object": "tv", "verb": "turn_on"},
			"say": "我们开始吧。", "pause_after": 0.35},
		{"actor": "jue_agent", "look_at_actor": "main_agent", "gesture": "nod",
			"expression": "happy", "say": "我准备好了。", "pause_after": 0.35},
	], "v08_full_performance")


## [D1] 构造最小合法文档，供各合同测试覆盖不同 Beat。
func _document(
	cast: Array,
	beats: Array,
	memory_summary: String = "contract_memory"
) -> Dictionary:
	return {
		"schema_version": 1,
		"story_id": "contract_story",
		"title": "合同剧情",
		"cast": cast,
		"beats": beats,
		"memory_summary": memory_summary,
	}


## [D2] 验证角色抵达目标路点的正常导航到达范围。
func _verify_position(agent: Node3D, waypoint: String, label: String) -> void:
	var target := RoomNavigation.new().get_waypoint(waypoint)
	var distance := agent.global_position.distance_to(target)
	_assert(distance <= 1.0, "%s missed %s by %.2fm position=%s target=%s" % [
		label, waypoint, distance, agent.global_position, target,
	])


## [D2] 按项目角色可见前向轴 `+Z` 验证角色水平朝向目标。
func _verify_facing(actor: Node3D, target: Node3D, label: String) -> void:
	var target_direction := target.global_position - actor.global_position
	target_direction.y = 0.0
	var visible_forward := actor.global_basis.z
	visible_forward.y = 0.0
	var alignment := visible_forward.normalized().dot(target_direction.normalized())
	_assert(alignment >= 0.8, "%s facing %.2f pos=%s target=%s yaw=%.1f" % [
		label, alignment, actor.global_position, target.global_position, rad_to_deg(actor.rotation.y),
	])


## [D2] 验证角色最终朝向一个语义物体。
func _verify_facing_object(actor: Node3D, object_id: String, label: String) -> void:
	var target = root.get_node("SemanticWorld").get_object(object_id)
	var target_direction: Vector3 = target.position - actor.global_position
	target_direction.y = 0.0
	var visible_forward := actor.global_basis.z
	visible_forward.y = 0.0
	var alignment := visible_forward.normalized().dot(target_direction.normalized())
	_assert(alignment >= 0.8, "%s facing %.2f" % [label, alignment])


## [D2] 验证导演 Cue 的角色归属、顺序和表情上下文。
func _verify_performance_order() -> void:
	_assert(_performance_cues.size() == 2, "unexpected story gesture count")
	_assert(_expression_cues.size() == 2, "unexpected story expression count")
	if _performance_cues.size() < 2 or _expression_cues.size() < 2:
		return
	_assert(_performance_cues[0] == {"gesture": "wave", "agent_id": "main_agent"}, "main wave missing")
	_assert(_performance_cues[1] == {"gesture": "nod", "agent_id": "jue_agent"}, "Jue nod missing")
	_assert(_expression_cues[0].agent_id == "main_agent", "main expression context missing")
	_assert(_expression_cues[1].agent_id == "jue_agent", "Jue expression context missing")


## [D2] 查询本轮是否向指定角色发出了指定动作。
func _has_performance_cue(agent_id: String, gesture: String) -> bool:
	for cue in _performance_cues:
		if cue.agent_id == agent_id and cue.gesture == gesture:
			return true
	return false


## [D2] 开始捕获导演来源的动作、表情和 Agent 对白。
func _begin_capture(bus: Node) -> void:
	_performance_cues.clear()
	_expression_cues.clear()
	_chat_entries.clear()
	bus.performance_cue.connect(_on_performance_cue)
	bus.expression_cue.connect(_on_expression_cue)
	bus.ui_add_chat_entry.connect(_on_chat_entry)


## [D2] 断开本轮导演信号捕获器。
func _end_capture(bus: Node) -> void:
	if bus.performance_cue.is_connected(_on_performance_cue):
		bus.performance_cue.disconnect(_on_performance_cue)
	if bus.expression_cue.is_connected(_on_expression_cue):
		bus.expression_cue.disconnect(_on_expression_cue)
	if bus.ui_add_chat_entry.is_connected(_on_chat_entry):
		bus.ui_add_chat_entry.disconnect(_on_chat_entry)


## [D2][T4.5] 等待导演回到 IDLE，并对悬挂演出实施超时保护。
func _wait_for_idle(director: Node, timeout_ms: int, message: String) -> void:
	var started_at := Time.get_ticks_msec()
	while int(director.get_diagnostics().phase) != 0:
		if Time.get_ticks_msec() - started_at > timeout_ms:
			_assert(false, message)
			director.cancel_story("test_timeout")
			return
		await physics_frame


## [D2] 捕获由 StoryDirector 下发的身体动作 Cue。
func _on_performance_cue(gesture: String, context: Dictionary) -> void:
	if String(context.get("source", "")) == "story_director":
		_performance_cues.append({"gesture": gesture, "agent_id": String(context.get("agent_id", ""))})


## [D2] 捕获由 StoryDirector 下发的表情 Cue。
func _on_expression_cue(expression: String, _intensity: float, context: Dictionary) -> void:
	if String(context.get("source", "")) == "story_director":
		_expression_cues.append({"expression": expression, "agent_id": String(context.get("agent_id", ""))})


## [D2] 捕获非玩家聊天条目以验证剧情对白顺序。
func _on_chat_entry(speaker: String, text: String, is_player: bool) -> void:
	if not is_player:
		_chat_entries.append({"speaker": speaker, "text": text})


## [D2] 查询本轮捕获的对白是否包含指定文本。
func _contains_chat(needle: String) -> bool:
	for entry in _chat_entries:
		if needle in String(entry.text):
			return true
	return false


## [D2][T4.5] 按唯一总结内容查询 Agent 的剧情记忆，不依赖环形数组长度。
func _has_memory(memory: Node, agent_id: String, marker: String) -> bool:
	for entry in memory.retrieve_relevant_for_agent(agent_id, marker, 20):
		if marker in String(entry.get("content", "")):
			return true
	return false


## [T4.5] 记录稳定失败并让场景清理完成，以保证可靠退出码。
func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	failed = true
	push_error("STORY_DIRECTOR_CHECK_FAIL: " + message)
