# Live ECNU acceptance for natural-language script → planned Story JSON → Godot direction.
# Requires configured data/llm_config.json and network access.
# Verifies: D3, D2, C5, X3

extends SceneTree

const SOURCE_SCRIPT := """
傍晚，诀正在安静看书。咕咕嘎嘎注意到她有点累，走过去挥手邀请她一起看电视。
诀先有一点意外，然后简短地答应。咕咕嘎嘎去打开电视，两个人分别走到沙发前
不同的位置坐下。最后诀说和朋友一起休息感觉不错，咕咕嘎嘎开心回应。
"""

var _plan_finished := false
var _plan_document: Dictionary = {}
var _plan_error := ""
var _failed := false
var _submitted_script := ""
var _required_agents: Array[String] = []


## [D3][X3] 延迟启动真实 ECNU 动态编剧验收。
func _init() -> void:
	call_deferred("_run")


## [D3][D2][C5] 提交未预制剧本，验证模型规划质量、导演执行和独立记忆。
func _run() -> void:
	var mode := root.get_node("ExperienceModeManager")
	mode.enter_performance_mode()
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var bus := root.get_node("MessageBus")
	var planner := root.get_node("StoryPlannerService")
	var director := root.get_node("StoryDirector")
	var memory := root.get_node("MemorySystem")
	root.get_node("TTSService").enabled = false
	bus.story_plan_ready.connect(_on_plan_ready)
	bus.story_plan_failed.connect(_on_plan_failed)
	_submitted_script = _resolve_source_script()
	_required_agents = _derive_required_agents(_submitted_script)
	if not planner.plan_script(_submitted_script):
		_fail("planner refused live request: %s" % planner.get_last_error())
		_finish(scene)
		return
	await _wait_for_plan(140000)
	if _plan_error.is_empty():
		_verify_plan_contract()
		await _wait_for_director(director, 75000)
		_verify_execution(director, memory)
	if not _failed and _plan_error.is_empty():
		print("ECNU_LIVE_STORY_PASS model=%s title=%s cast=%s beats=%d repairs=%d retries=%d" % [
			root.get_node("CognitiveCycle").llm_model,
			_plan_document.get("title", ""),
			_plan_document.get("cast", []),
			_plan_document.get("beats", []).size(),
			int(planner.get_diagnostics().repair_attempts),
			int(planner.get_diagnostics().transport_retries),
		])
	_finish(scene)


## [D3][X3] 允许通过 `-- <剧本>` 复用真实测试，未传参数时使用内置邀约场景。
func _resolve_source_script() -> String:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		return SOURCE_SCRIPT
	return " ".join(args).strip_edges()


## [D3][C6.2] 把玩家剧本中点名的注册角色转为本次必须出现的 Agent ID。
func _derive_required_agents(source: String) -> Array[String]:
	var required: Array[String] = []
	var registry := root.get_node("CharacterAdapterRegistry")
	for agent_id in registry.get_registered_agent_ids():
		var adapter: Dictionary = registry.get_character_adapter(agent_id)
		var display_name := String(adapter.get(
			"display_name",
			root.get_node("CodifiedProfile").get_agent_display_name(agent_id),
		))
		if not display_name.is_empty() and display_name in source:
			required.append(agent_id)
	return required


## [D3] 等待 LLM 规划或失败信号，实施真实网络超时。
func _wait_for_plan(timeout_ms: int) -> void:
	var started := Time.get_ticks_msec()
	while not _plan_finished:
		if Time.get_ticks_msec() - started > timeout_ms:
			_fail("ECNU planning timed out")
			return
		await process_frame


## [D3][D2] 等待已验证剧本执行完成。
func _wait_for_director(director: Node, timeout_ms: int) -> void:
	var started := Time.get_ticks_msec()
	while int(director.get_diagnostics().phase) != 0:
		if Time.get_ticks_msec() - started > timeout_ms:
			director.cancel_story("ecnu_live_timeout")
			_fail("planned story execution timed out")
			return
		await process_frame


## [D3] 检查真实模型是否规划了双角色、多 Beat 和具身表现，而非只返回对白。
func _verify_plan_contract() -> void:
	var cast: Array = _plan_document.get("cast", [])
	var beats: Array = _plan_document.get("beats", [])
	_assert(not _required_agents.is_empty(), "source script did not name any registered actor")
	for agent_id in _required_agents:
		_assert(agent_id in cast, "ECNU plan omitted named actor %s" % agent_id)
	_assert(beats.size() >= 4, "ECNU plan is too short for a multi-character scene")
	var actors := {}
	var has_movement := false
	var has_performance := false
	var has_dialogue := false
	var interactions: Dictionary = {}
	for beat in beats:
		actors[String(beat.get("actor", ""))] = true
		has_movement = has_movement or beat.has("move_to")
		has_performance = has_performance or beat.has("gesture") or beat.has("expression")
		has_dialogue = has_dialogue or beat.has("say")
		if beat.get("interact") is Dictionary:
			var interaction: Dictionary = beat["interact"]
			interactions["%s.%s" % [
				interaction.get("object", ""), interaction.get("verb", ""),
			]] = true
	for agent_id in _required_agents:
		_assert(actors.has(agent_id), "named actor %s received no beats" % agent_id)
	_assert(has_movement, "ECNU plan contains no embodied movement")
	_assert(has_performance, "ECNU plan contains no gesture or expression")
	_assert(has_dialogue, "ECNU plan contains no dialogue")
	_assert(
		not String(_plan_document.get("memory_summary", "")).is_empty(),
		"ECNU plan omitted memory_summary",
	)
	if "浇水" in _submitted_script:
		_assert(interactions.has("plant.water"), "ECNU plan omitted requested plant.water")
	if "读一会儿书" in _submitted_script:
		_assert(interactions.has("book.read"), "ECNU plan omitted requested book.read")
	if "关闭壁灯" in _submitted_script:
		_assert(interactions.has("room_lights.turn_off"), "ECNU plan omitted room_lights.turn_off")
	if "浏览书架" in _submitted_script:
		_assert(interactions.has("bookshelf.browse"), "ECNU plan omitted bookshelf.browse")
	if "查看茶几" in _submitted_script:
		_assert(interactions.has("coffee_table.inspect"), "ECNU plan omitted coffee_table.inspect")


## [D2][C5] 验证导演成功完成，并为每名被点名角色增加剧情记忆。
func _verify_execution(director: Node, memory: Node) -> void:
	_assert(
		String(director.get_diagnostics().last_error).is_empty(),
		"director rejected live plan: %s" % director.get_diagnostics().last_error,
	)
	var summary := String(_plan_document.get("memory_summary", ""))
	for agent_id in _required_agents:
		_assert(
			_has_story_memory(memory, agent_id, summary),
			"%s did not receive live-story memory" % agent_id,
		)


## [C5] 在定长环形记忆中按本次动态总结查找剧情记录。
func _has_story_memory(memory: Node, agent_id: String, summary: String) -> bool:
	var episodes: Array = memory.agent_memories[agent_id]["episodes"]
	for entry in episodes:
		var content := String(entry.get("content", ""))
		if content.begins_with("[剧情]") and summary in content:
			return true
	return false


## [D3] 捕获成功规划文档。
func _on_plan_ready(document: Dictionary) -> void:
	_plan_document = document.duplicate(true)
	print("ECNU_LIVE_PLAN title=%s cast=%s beats=%d route=%s" % [
		document.get("title", ""),
		document.get("cast", []),
		document.get("beats", []).size(),
		_summarize_plan_route(document.get("beats", [])),
	])
	_plan_finished = true


## [D3] 输出不含 API Key 和完整对白的模型规划摘要，便于定位走位/能力问题。
func _summarize_plan_route(beats: Array) -> String:
	var summary: Array[String] = []
	for beat in beats:
		if not beat is Dictionary:
			continue
		summary.append("%s:%s:%s" % [
			beat.get("actor", ""),
			JSON.stringify(beat.get("move_to", {})),
			"%s/%s" % [
				beat.get("gesture", ""),
				JSON.stringify(beat.get("interact", {})),
			],
		])
	return "|".join(summary)


## [D3][X3] 捕获网络、解析、校验或自动修复失败。
func _on_plan_failed(reason: String) -> void:
	_plan_error = reason
	_plan_finished = true
	_fail(reason)


## [T4.5] 记录失败并保留清理机会。
func _fail(message: String) -> void:
	_failed = true
	push_error("ECNU_LIVE_STORY_FAIL: " + message)


## [T4.5] 累积合同失败。
func _assert(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


## [T4.5] 关闭自主调度、释放场景并返回可靠退出码。
func _finish(scene: Node) -> void:
	root.get_node("AutonomousBehaviorSystem").set_scheduler_enabled(false)
	scene.free()
	quit(1 if _failed or not _plan_error.is_empty() else 0)
