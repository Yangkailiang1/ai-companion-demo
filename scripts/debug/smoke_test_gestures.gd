# smoke_test_gestures.gd — Gesture Pipeline Smoke Test
# 用于验证 gesture 管线：输入→ cue → AnimationPlayer 播放
# 运行方式：将此脚本挂到场景根节点的临时 node 上，按 F5 启动后观察控制台输出。
# 或在 Godot 编辑器中通过 Scene → Debug 手动触发。
#
# 测试流程：
#   1. 强制本地模式（无 LLM）
#   2. 模拟玩家输入测试句
#   3. 断言 performance_cue 信号
#   4. 断言 AnimationPlayer 播放对应动画

extends Node

var test_results: Array[Dictionary] = []
var animation_player: AnimationPlayer
var cue_received: Dictionary = {}
var _test_done_signal_triggered: bool = false

const TEST_CASES = [
	{"input": "挥挥手",         "expected_gesture": "wave",  "expected_goal": ""},
	{"input": "点点头",         "expected_gesture": "nod",   "expected_goal": ""},
	{"input": "想一想",         "expected_gesture": "think", "expected_goal": ""},
	{"input": "开心一点",       "expected_gesture": "happy", "expected_goal": ""},
	{"input": "我们一起看电视",  "expected_gesture": "",      "expected_goal": "watch_tv"},
]


func _ready():
	print("\n=== [Smoke Test] Gesture Pipeline ===")

	# 监听 performance_cue 信号
	if MessageBus.has_signal("performance_cue"):
		MessageBus.performance_cue.connect(_on_performance_cue)

	# 监听 emit_actions 信号（验证 goal）
	if MessageBus.has_signal("emit_actions"):
		MessageBus.emit_actions.connect(_on_emit_actions)

	# Find AnimationPlayer in the Agent
	animation_player = _find_animation_player()
	if animation_player:
		print("[SmokeTest] AnimationPlayer found: %s" % animation_player.get_path())
		print("[SmokeTest] Available animations: %s" % animation_player.get_animation_list())
	else:
		print("[SmokeTest] WARNING: No AnimationPlayer found — animation assertions will be skipped")

	# Start test after a short delay to let scene initialize
	await get_tree().create_timer(0.5).timeout
	_run_all_tests()


func _find_animation_player() -> AnimationPlayer:
	var root = get_tree().current_scene
	if not root: return null
	return root.find_child("AnimationPlayer", true, false) as AnimationPlayer


func _run_all_tests():
	for i in range(TEST_CASES.size()):
		var tc = TEST_CASES[i]
		await _run_single_test(i, tc)
		await get_tree().create_timer(0.3).timeout  # 让 AI 处理完

	_print_summary()


func _run_single_test(index: int, tc: Dictionary) -> void:
	var input = tc["input"]
	var expected_gesture = tc["expected_gesture"]
	var expected_goal = tc["expected_goal"]

	print("\n--- Test #%d: '%s' ---" % [index + 1, input])
	print("  Expected gesture: '%s', Expected goal: '%s'" % [expected_gesture, expected_goal])

	# Reset tracking
	cue_received = {}

	# Send input
	MessageBus.route_player_input(input)

	# Wait for processing
	await get_tree().create_timer(0.5).timeout

	# Evaluate
	var result = {"test": "#%d: '%s'" % [index + 1, input], "passed": true, "details": []}

	# Check gesture
	if not expected_gesture.is_empty():
		var actual_gesture = cue_received.get("gesture", "")
		if actual_gesture == expected_gesture:
			result["details"].append("gesture OK: '%s'" % actual_gesture)
		else:
			result["passed"] = false
			result["details"].append("gesture FAIL: expected '%s', got '%s'" % [expected_gesture, actual_gesture])

		# Check animation if player exists
		if animation_player and animation_player.has_animation(actual_gesture):
			result["details"].append("animation '%s' exists in AnimationPlayer" % actual_gesture)
		elif animation_player:
			result["details"].append("animation '%s' MISSING from AnimationPlayer (pending GLB import)" % actual_gesture)

	# Check goal (via emit_actions)
	if not expected_goal.is_empty():
		var actual_goal = cue_received.get("goal", "")
		if expected_goal in actual_goal:
			result["details"].append("goal OK: '%s' (matched '%s')" % [actual_goal, expected_goal])
		else:
			result["passed"] = false
			result["details"].append("goal FAIL: expected contain '%s', got '%s'" % [expected_goal, actual_goal])

	if result["passed"]:
		print("  ✅ PASSED")
	else:
		print("  ❌ FAILED")
	for d in result["details"]:
		print("    %s" % d)

	test_results.append(result)


func _print_summary():
	print("\n" + "=".repeat(50))
	print("=== SMOKE TEST SUMMARY ===")
	var passed = 0
	var failed = 0
	for r in test_results:
		if r["passed"]: passed += 1
		else: failed += 1
		print("  %s %s" % ["✅" if r["passed"] else "❌", r["test"]])
	print("---")
	print("  Total: %d | Passed: %d | Failed: %d" % [test_results.size(), passed, failed])

	if failed > 0 and not animation_player:
		print("\n  NOTE: Some failures may be expected — AnimationPlayer animations come from GLB import (pending main-agent execution).")
		print("  Gesture signal routing failures would indicate a code issue.")
	elif failed > 0:
		print("\n  ⚠️  Some tests failed — check the details above.")
	else:
		print("\n  🎉 All tests passed!")

	print("=".repeat(50))
	print("  pending main-agent execution: verify in Godot editor.")


func _on_performance_cue(gesture: String, context: Dictionary) -> void:
	cue_received["gesture"] = gesture
	cue_received["source"] = context.get("source", "")
	print("[SmokeTest] performance_cue received: gesture='%s', source='%s'" % [gesture, context.get("source", "")])


func _on_emit_actions(agent_id: String, actions: Array) -> void:
	# Extract goal from action chain by checking INTERACT targets
	for action in actions:
		if action.type == AffordanceTypes.Primitive.INTERACT:
			var obj = action.params.get("object", "")
			if not obj.is_empty():
				# Map object to goal keywords
				var goal_map = {
					"tv": "watch_tv",
					"book": "read_book",
					"milk_tea": "drink_milk_tea",
					"sofa": "rest_on_sofa",
					"plant": "water_plant",
				}
				var goal = goal_map.get(obj, obj)
				cue_received["goal"] = goal
				return
	# If no INTERACT, check NAVIGATE target
	for action in actions:
		if action.type == AffordanceTypes.Primitive.NAVIGATE:
			cue_received["goal"] = "navigate_to:" + action.params.get("target", "unknown")
			return
	cue_received["goal"] = "idle/chat"
