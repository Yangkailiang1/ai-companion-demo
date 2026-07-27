# Headless acceptance for free-life and LLM-planned performance modes.
# Verifies: D2, D3, C9, X3

extends SceneTree

var failed := false
var _trigger_count := 0
var _plan_ready_count := 0
var _plan_failed_count := 0
var _dialogues: Array[String] = []


## [D3][C9] 延迟启动双模式集成验收。
func _init() -> void:
	call_deferred("_run")


## [D2][D3][C9] 组合模式切换、提示上下文、注入规划和自由对话验收。
func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var bus := root.get_node("MessageBus")
	var mode := root.get_node("ExperienceModeManager")
	var planner := root.get_node("StoryPlannerService")
	var director := root.get_node("StoryDirector")
	var autonomy := root.get_node("AutonomousBehaviorSystem")
	var cognitive := root.get_node("CognitiveCycle")
	cognitive.llm_api_url = ""
	cognitive.llm_api_key = ""
	_connect_capture(bus)

	_verify_prompt_context()
	_verify_generic_affordance()
	_verify_enter_performance(bus, mode, autonomy)
	_verify_unconfigured_planner_route(bus, planner, director)
	await _verify_injected_plan(planner, director, mode, autonomy)
	_verify_return_to_free(bus, mode, autonomy)
	await _verify_free_dialogue_route(bus)

	autonomy.set_scheduler_enabled(false)
	if not failed:
		print("EXPERIENCE_MODES_CHECK_PASS ready=%d failed=%d triggers=%d" % [
			_plan_ready_count, _plan_failed_count, _trigger_count,
		])
	scene.free()
	quit(1 if failed else 0)


## [D3] 验证 LLM 能看到角色、人设、物体能力和安全站位，而非凭空规划。
func _verify_prompt_context() -> void:
	var builder = load("res://scripts/directing/story_planning_prompt_builder.gd").new()
	var prompt: String = builder.build("两个人一起看电视")
	for token in ["main_agent", "jue_agent", "咕咕嘎嘎", "诀", "sofa_seat_left", "tv", "turn_on"]:
		_assert(token in prompt, "planner prompt missing context: %s" % token)


## [D3][S3.2] 验证 Planner 看到的通用物体 affordance 在导演侧确实可执行。
func _verify_generic_affordance() -> void:
	var book = root.get_node("SemanticWorld").get_object("book")
	var result: Dictionary = book.godot_node.perform_interaction("read", "jue_agent")
	_assert(bool(result.get("handled", false)), "advertised book.read was not executable")
	_assert("诀" in String(book.state), "generic interaction did not update semantic state")


## [D3][C9] 验证显式进入演出模式会暂停自主调度。
func _verify_enter_performance(bus: Node, mode: Node, autonomy: Node) -> void:
	autonomy.set_scheduler_enabled(true)
	bus.route_player_input("!演出")
	_assert(mode.get_mode_name() == "performance", "performance command did not switch mode")
	_assert(not bool(autonomy.get("_scheduler_enabled")), "autonomy stayed enabled in performance mode")


## [D3][X3] 无模型配置时，演出模式普通输入必须报错且不能进入角色认知。
func _verify_unconfigured_planner_route(bus: Node, planner: Node, director: Node) -> void:
	var triggers_before := _trigger_count
	bus.route_player_input("咕咕嘎嘎邀请诀一起看电视")
	_assert(_plan_failed_count == 1, "missing LLM configuration did not produce planner failure")
	_assert("配置" in planner.get_last_error(), "planner failure did not explain configuration")
	_assert(_trigger_count == triggers_before, "performance script leaked into character cognition")
	_assert(int(director.get_diagnostics().phase) == 0, "failed plan unexpectedly started director")


## [D3][D2] 注入等价 LLM JSON，验证校验后能执行动作、交互和双角色对白。
func _verify_injected_plan(
	planner: Node,
	director: Node,
	mode: Node,
	autonomy: Node
) -> void:
	var invalid := {"story_id": "bad", "title": "bad", "cast": ["ghost"], "beats": []}
	_assert(not planner.accept_planner_output(JSON.stringify(invalid)), "invalid LLM cast was accepted")
	var document := {
		"schema_version": 1,
		"story_id": "injected_llm_story",
		"title": "模型编排的电视邀约",
		"cast": ["main_agent", "jue_agent"],
		"beats": [
			{"actor": "main_agent", "say": "", "pause_after": 0.1},
			{"actor": "main_agent", "look_at_object": "tv",
				"interact": {"object": "tv", "verb": "turn_on"},
				"gesture": "wave", "expression": "happy",
				"say": "诀，我们看一会儿电视吧。", "pause_after": 0.15},
			{"actor": "jue_agent", "look_at_actor": "main_agent",
				"gesture": "nod", "expression": "happy",
				"say": "好，我陪你。", "pause_after": 0.15},
		],
		"memory_summary": "injected_llm_story_memory",
	}
	_assert(planner.accept_planner_output(JSON.stringify(document)), "valid injected LLM plan was rejected")
	await _wait_for_director(director, 10000)
	_assert(_plan_ready_count == 1, "valid plan did not emit ready")
	_assert(_contains_dialogue("我们看一会儿电视"), "planned main dialogue missing")
	_assert(_contains_dialogue("我陪你"), "planned Jue dialogue missing")
	_assert(mode.get_mode_name() == "performance", "director completion exited performance mode")
	_assert(not bool(autonomy.get("_scheduler_enabled")), "autonomy resumed inside performance mode")


## [C9][D3] 验证返回自由模式恢复自主调度。
func _verify_return_to_free(bus: Node, mode: Node, autonomy: Node) -> void:
	bus.route_player_input("!自由")
	_assert(mode.get_mode_name() == "free", "free command did not switch mode")
	_assert(bool(autonomy.get("_scheduler_enabled")), "autonomy did not resume in free mode")


## [C9][T1] 自由模式普通输入必须重新进入目标角色认知循环。
func _verify_free_dialogue_route(bus: Node) -> void:
	var before := _trigger_count
	bus.route_player_input("@诀 你好")
	await process_frame
	_assert(_trigger_count >= before + 1, "free-mode dialogue did not enter cognition")


## [D2][T4.5] 等待导演完成，超时则取消并记录稳定失败。
func _wait_for_director(director: Node, timeout_ms: int) -> void:
	var started := Time.get_ticks_msec()
	while int(director.get_diagnostics().phase) != 0:
		if Time.get_ticks_msec() - started > timeout_ms:
			_assert(false, "planned story timed out")
			director.cancel_story("test_timeout")
			return
		await process_frame


## [D3][C9] 捕获模式规划和角色认知边界信号。
func _connect_capture(bus: Node) -> void:
	bus.agent_trigger_cycle.connect(func(
		_agent_id: String, _source: AffordanceTypes.TriggerSource, _data: Dictionary
	): _trigger_count += 1)
	bus.story_plan_ready.connect(func(_document: Dictionary): _plan_ready_count += 1)
	bus.story_plan_failed.connect(func(_reason: String): _plan_failed_count += 1)
	bus.ui_add_chat_entry.connect(func(_speaker: String, text: String, is_player: bool):
		if not is_player:
			_dialogues.append(text)
	)


## [D2] 查询已路由的演出对白。
func _contains_dialogue(needle: String) -> bool:
	for text in _dialogues:
		if needle in text:
			return true
	return false


## [T4.5] 累积失败并确保退出码可靠。
func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	failed = true
	push_error("EXPERIENCE_MODES_CHECK_FAIL: " + message)
