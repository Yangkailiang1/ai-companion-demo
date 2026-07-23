extends SceneTree

const ExpressionIntentRouterScript = preload("res://scripts/characters/expression_intent_router.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var router = ExpressionIntentRouterScript.new()
	_assert(router.is_ready(), "expression router must load expression_library.json")
	var shy := router.route("有点害羞但开心地笑", "neutral", 0.8)
	_assert(String(shy.get("expression", "")) == "shy_happy", "shy query should resolve to shy_happy")
	var shy_weights: Dictionary = shy.get("morph_weights", {})
	_assert(float(shy_weights.get("joy", 0.0)) > 0.2, "shy_happy should include joy")
	_assert(float(shy_weights.get("blink", 0.0)) > 0.02, "shy_happy should include blink")
	var confused := router.route("疑惑地歪头，没听懂", "neutral", 0.75)
	_assert(String(confused.get("expression", "")) == "confused", "confused query should resolve to confused")
	var scene: PackedScene = load("res://scenes/living_room.tscn")
	var room := scene.instantiate()
	root.add_child(room)
	await process_frame
	await process_frame
	var driver = room.get_node_or_null("Agent/CharacterExpressionDriver")
	_assert(driver != null, "living room must include CharacterExpressionDriver")
	var message_bus := root.get_node_or_null("MessageBus")
	_assert(message_bus != null, "MessageBus autoload must exist")
	message_bus.emit_signal("expression_blend_cue", shy, {"source": "expression_router_check"})
	await create_timer(0.32).timeout
	_assert(_max_morph_value(room, "joy") > 0.2, "expression blend cue must drive joy morph")
	_assert(_max_morph_value(room, "blink") > 0.02, "expression blend cue must drive blink morph")
	room.queue_free()
	await process_frame
	print("EXPRESSION_ROUTER_CHECK_PASS shy=%s confused=%s" % [shy.get("provider", ""), confused.get("provider", "")])
	quit(0)


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
	push_error("EXPRESSION_ROUTER_CHECK_FAIL: %s" % message)
	quit(1)
	assert(condition, message)
