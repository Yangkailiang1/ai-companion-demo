extends SceneTree

const MotionIntentRouterScript = preload("res://scripts/characters/motion_intent_router.gd")

const PENGUIN_BONES := [
	"root", "hips", "spine", "chest", "neck", "head",
	"shoulder.L", "upper_arm.L", "lower_arm.L", "hand.L",
	"shoulder.R", "upper_arm.R", "lower_arm.R", "hand.R",
	"upper_leg.L", "lower_leg.L", "foot.L", "toes.L",
	"upper_leg.R", "lower_leg.R", "foot.R", "toes.R",
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var router = MotionIntentRouterScript.new()
	_assert(router.is_ready(), "router catalogs must load")
	var cases := [
		["请挥挥手", "wave", "library", "happy"],
		["点点头表示同意", "nod", "library", "happy"],
		["让我想一想", "think", "library", "neutral"],
		["开心一点", "happy", "library", "happy"],
		["请坐下休息", "sit", "library", "neutral"],
		["在房间里逛逛", "walk", "library", "neutral"],
		["please wave hello", "wave", "library", "happy"],
		["please think about it", "think", "library", "neutral"],
		["我今天很难过", "talk", "library", "sad"],
		["我现在很生气", "talk", "library", "angry"],
		["眨眨眼", "talk", "library", "blink"],
		["今天天气怎么样", "talk", "library", "talk"],
		["表演一个侧手翻", "idle", "light_t2m", "neutral"],
		["dance in a circle", "idle", "light_t2m", "neutral"],
		["不要挥手", "talk", "library", "talk"],
		["你会侧手翻吗", "talk", "library", "talk"],
	]
	for case in cases:
		var decision := router.route(case[0])
		_assert(decision["clip"] == case[1], "%s clip expected %s got %s" % [case[0], case[1], decision["clip"]])
		_assert(decision["provider"] == case[2], "%s provider mismatch" % case[0])
		_assert(decision["expression"] == case[3], "%s expression expected %s got %s" % [case[0], case[3], decision["expression"]])
		if decision["provider"] == "light_t2m":
			_assert(not String(decision["generation_prompt"]).is_empty(), "generated route needs a provider prompt")
			_assert(PerformanceCueTypes.is_valid_gesture(decision["fallback_clip"]), "generated route needs a safe fallback")

	_validate_structured_router(router)
	_validate_bone_map()
	_validate_expression_catalog()
	await _validate_scene_driver()
	print("MOTION_EXPRESSION_BRIDGE_PASS prompts=%d joints=22" % cases.size())
	quit(0)


func _validate_structured_router(router) -> void:
	var tv: Dictionary = router.route("我们一起去看电视吧")
	_assert(tv.get("goal", "") == "watch_tv", "TV intent must resolve to watch_tv")
	_assert(tv.get("target", "") == "tv", "TV intent must target tv")
	_assert(tv.get("locomotion", "") == "walk_to", "TV intent must request walk_to")
	var patrol: Dictionary = router.route("请绕着整个房间转一圈")
	_assert(patrol.get("goal", "") == "patrol_room", "room lap intent must resolve to patrol_room")
	_assert(patrol.get("target", "") == "room_perimeter", "room lap intent must target room_perimeter")
	var come_here: Dictionary = router.route("过来一下")
	_assert(come_here.get("target", "") == "room_center", "come-here intent must use a safe player-area waypoint")
	var plan: Array = come_here.get("plan", [])
	_assert(plan.size() == 1 and plan[0].get("waypoint", "") == "room_center", "come-here intent must emit a safe waypoint plan")


func _validate_bone_map() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/humanml3d_penguin_bone_map.json"))
	_assert(parsed is Dictionary, "bone map must be valid JSON")
	var joints: Array = parsed.get("joints", [])
	_assert(joints.size() == 22, "bone map must contain exactly 22 joints")
	for index in range(joints.size()):
		var joint: Dictionary = joints[index]
		_assert(joint.get("index", -1) == index, "bone map indices must be contiguous")
		_assert(joint.get("target", "") in PENGUIN_BONES, "unknown penguin target bone: %s" % joint.get("target", ""))


func _validate_expression_catalog() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/expression_catalog.json"))
	_assert(parsed is Dictionary, "expression catalog must be valid JSON")
	var expressions: Dictionary = parsed.get("expressions", {})
	for required in ["neutral", "happy", "angry", "sad", "surprised", "excited", "bored", "blink", "talk"]:
		_assert(expressions.has(required), "missing expression: %s" % required)
		_assert(expressions[required].get("morph_weights", {}) is Dictionary, "expression morph_weights must be a dictionary")


func _validate_scene_driver() -> void:
	var scene: PackedScene = load("res://scenes/living_room.tscn")
	var room := scene.instantiate()
	root.add_child(room)
	await process_frame
	await process_frame
	var driver = room.get_node_or_null("Agent/CharacterExpressionDriver")
	_assert(driver != null, "living room must include CharacterExpressionDriver")
	var morph_names: PackedStringArray = driver.get_available_morph_names()
	_assert("joy" in morph_names, "penguin GLB must expose joy morph")
	_assert("blink" in morph_names, "penguin GLB must expose blink morph")
	var message_bus := root.get_node_or_null("MessageBus")
	_assert(message_bus != null, "MessageBus autoload must exist")
	message_bus.emit_signal("expression_cue", "happy", 1.0, {"source": "bridge_check"})
	await create_timer(0.2).timeout
	_assert(_max_morph_value(room, "joy") > 0.5, "happy cue must drive joy morph")
	message_bus.emit_signal("expression_cue", "blink", 1.0, {"source": "bridge_check"})
	await create_timer(0.14).timeout
	_assert(_max_morph_value(room, "blink") > 0.5, "blink cue must close the eyes")
	await create_timer(0.25).timeout
	_assert(_max_morph_value(room, "blink") < 0.1, "transient blink must return to neutral")
	var animation_driver = room.get_node_or_null("Agent/CharacterAnimationDriver")
	_assert(animation_driver != null, "living room must include CharacterAnimationDriver")
	message_bus.emit_signal("performance_cue", "walk", {"source": "bridge_check"})
	await create_timer(0.1).timeout
	message_bus.emit_signal("expression_cue", "angry", 0.8, {"source": "bridge_check"})
	await create_timer(0.16).timeout
	_assert(animation_driver.get_current_gesture() == "walk", "expression cue must not interrupt locomotion")
	room.queue_free()
	await process_frame


func _max_morph_value(node: Node, normalized_name: String) -> float:
	var maximum := 0.0
	if node is MeshInstance3D and node.mesh:
		var array_mesh := node.mesh as ArrayMesh
		if array_mesh:
			for index in range(array_mesh.get_blend_shape_count()):
				var name := String(array_mesh.get_blend_shape_name(index)).to_lower().replace(".", "_")
				if name == normalized_name:
					maximum = maxf(maximum, node.get_blend_shape_value(index))
	for child in node.get_children():
		maximum = maxf(maximum, _max_morph_value(child, normalized_name))
	return maximum


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("MOTION_EXPRESSION_BRIDGE_FAIL: %s" % message)
	quit(1)
	assert(condition, message)
