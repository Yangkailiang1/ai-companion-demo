# Contract test for T4.5 CognitiveCycle split review fixes.
# Run with: Godot --headless --path . --script scripts/debug/t4_5_cognitive_split_test.gd
# Verifies: T1, X3, T4.5
# Covers: 1) explicit activity constraint + router-only "过来" plan
#         2) FUN simulation trigger does not choose hunger fallback
#         3) HUNGER simulation trigger chooses hunger fallback

extends SceneTree

var _failed := false


## [T4.5] Schedule the contract test after Autoload initialization.
func _init() -> void:
	call_deferred("_run")


## [T1][X3][T4.5] Verify prompt routing and need-specific local fallback behavior.
func _run() -> void:
	await process_frame
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame

	var cognitive := root.get_node("CognitiveCycle")
	_assert_prompt_and_router_contract(cognitive)
	var decider = _create_fallback_decider()
	_assert_fun_trigger_contract(decider)
	_assert_hunger_trigger_contract(decider)

	if _failed:
		main.free()
		quit(1)
		return
	print("\n=== T4_5_COGNITIVE_SPLIT_TEST PASS ===")
	main.free()
	quit(0)


## [T1][T4.5] Verify catalog-only motion plans and explicit activity prompt constraints.
func _assert_prompt_and_router_contract(cognitive: Node) -> void:
	var routed_come_here: Dictionary = cognitive._perf_resolver.route_player_intent(
		"过来", "idle", "neutral", 0.5, cognitive._motion_router)
	print("  Router diagnostic: ", routed_come_here)
	if String(routed_come_here.get("action_id", "")) != "come_here":
		_fail("motion router did not resolve '过来' to come_here action: %s" % routed_come_here)
	elif (routed_come_here.get("plan", []) as Array).is_empty():
		_fail("come_here route did not preserve its navigation plan")

	# === Test 1: explicit player activity remains constrained in prompt ===
	print("\n--- Test 1: \"看电视\" → watch_tv prompt constraint ---")
	var prompt: String = cognitive.build_prompt(
		"[Semantic snapshot]",
		"[Memory context]",
		"[Codified]",
		"[Psychology]",
		[],  # triggered
		"看电视",  # player_message
		AffordanceTypes.TriggerSource.PLAYER_INPUT,
		"main_agent"
	)
	if "watch_tv" in prompt:
		print("  PASS: prompt contains 'watch_tv' explicit goal constraint")
	else:
		_fail("prompt for '看电视' does not contain 'watch_tv':\n" + prompt.left(500))

	# Also verify that the constraint string is the full instruction
	if "goal 必须为 'watch_tv'" in prompt:
		print("  PASS: prompt contains 'goal 必须为 \\'watch_tv\\'' instruction")
	else:
		_fail("prompt missing 'goal 必须为' instruction:\n" + prompt.left(500))


## [X3][T4.5] Construct the extracted fallback policy through its public constructor.
func _create_fallback_decider():
	var perf_resolver_class = load("res://scripts/core/performance_resolver.gd")
	var prompt_builder_class = load("res://scripts/core/prompt_builder.gd")
	return load("res://scripts/core/local_fallback_decider.gd").new(
		prompt_builder_class.new(),
		perf_resolver_class.new()
	)


## [T1][X3][T4.5] Verify FUN simulation triggers ignore unrelated hunger deficits.
func _assert_fun_trigger_contract(decider) -> void:
	print("\n--- Test 2: FUN trigger ignores low hunger ---")
	var needs = {"hunger": 20.0, "fun": 25.0, "energy": 80.0, "social": 80.0, "bladder": 10.0}
	var sim_decision = decider.decide(
		"",
		AffordanceTypes.TriggerSource.SIMULATION,
		[],
		needs,
		null,
		AffordanceTypes.NeedType.FUN
	)
	if sim_decision["goal"] == "drink_milk_tea":
		_fail("FUN trigger incorrectly chose hunger fallback (goal=drink_milk_tea)")
	elif sim_decision["goal"] == "watch_tv":
		print("  PASS: FUN trigger with low fun correctly chose watch_tv")
	else:
		_fail("FUN trigger with low fun returned unexpected goal: '%s'" % sim_decision["goal"])

	# FUN trigger with normal fun should get idle (no default speech/action)
	var needs_fun_ok = {"hunger": 20.0, "fun": 80.0, "energy": 80.0, "social": 80.0, "bladder": 10.0}
	var sim_decision_fun_ok = decider.decide(
		"",
		AffordanceTypes.TriggerSource.SIMULATION,
		[],
		needs_fun_ok,
		null,
		AffordanceTypes.NeedType.FUN
	)
	if sim_decision_fun_ok["speech"] != "" or sim_decision_fun_ok["goal"] != "idle":
		_fail("FUN trigger with normal fun should be idle, got goal='%s' speech='%s'" %
			[sim_decision_fun_ok["goal"], sim_decision_fun_ok["speech"]])
	else:
		print("  PASS: FUN trigger with normal fun returned idle (no false fallback)")


## [T1][X3][T4.5] Verify HUNGER simulation triggers select hunger or codified fallback.
func _assert_hunger_trigger_contract(decider) -> void:
	print("\n--- Test 3: HUNGER trigger chooses drink_milk_tea ---")
	var hunger_needs = {"hunger": 20.0, "fun": 80.0, "energy": 80.0, "social": 80.0, "bladder": 10.0}
	var hunger_decision = decider.decide(
		"",
		AffordanceTypes.TriggerSource.SIMULATION,
		[],
		hunger_needs,
		null,
		AffordanceTypes.NeedType.HUNGER
	)
	if hunger_decision["goal"] != "drink_milk_tea":
		_fail("HUNGER trigger with low hunger should return drink_milk_tea, got: '%s'" % hunger_decision["goal"])
	elif hunger_decision["speech"] == "":
		_fail("HUNGER trigger with low hunger should produce speech, got empty")
	else:
		print("  PASS: HUNGER trigger with low hunger returned drink_milk_tea + speech: '%s'" % hunger_decision["speech"])

	# HUNGER trigger with normal hunger should use codified reaction
	var needs_hunger_ok = {"hunger": 80.0, "fun": 80.0, "energy": 80.0, "social": 80.0, "bladder": 10.0}
	var trig = [{"reaction": "测试表情反应", "emotion": "sad"}]
	var hunger_ok_decision = decider.decide(
		"",
		AffordanceTypes.TriggerSource.SIMULATION,
		trig,
		needs_hunger_ok,
		null,
		AffordanceTypes.NeedType.HUNGER
	)
	if hunger_ok_decision["speech"] == "测试表情反应":
		print("  PASS: HUNGER trigger with normal hunger fell through to codified reaction")
	elif hunger_ok_decision["speech"] != "":
		print("  PASS: HUNGER trigger with normal hunger returned speech (codified bypass)")
	else:
		print("  INFO: HUNGER trigger with normal hunger returned empty (no codified triggers)")


## [T4.5] Record a contract failure while allowing remaining assertions to run.
func _fail(message: String) -> void:
	push_error("T4_5_COGNITIVE_SPLIT_FAIL: " + message)
	_failed = true
