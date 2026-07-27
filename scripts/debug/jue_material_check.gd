# Roadmap: C8.1, C8.2
# Responsibility: 验证诀的可见 LOD0 身体与服装使用真实贴图材质；不做视觉主观评分。
# Tests: 本文件为 Godot headless 合同验收。
# Verifies: C8.1, C8.2

extends SceneTree


## [C8.1] 延迟启动材质合同验收。
func _init() -> void:
	call_deferred("_run")


## [C8.1][C8.2] 实例化客厅并验证身体、服装、头发和眼睛的贴图绑定。
func _run() -> void:
	var room := (load("res://scenes/living_room.tscn") as PackedScene).instantiate()
	root.add_child(room)
	await process_frame
	await process_frame
	var visual := room.get_node("JueAgent/JueModelRoot")
	var diagnostics: Dictionary = visual.get_material_diagnostics()
	if not bool(diagnostics.get("local_model_loaded", false)):
		_assert(
			visual.get_node_or_null("PublicPlaceholder") != null,
			"public checkout must show a placeholder",
		)
		print("JUE_MATERIAL_CHECK_PASS local_asset=absent placeholder=ready")
		room.queue_free()
		await process_frame
		quit(0)
		return
	var bindings: Dictionary = diagnostics.get("adapted_meshes", {})
	var textured: Array = diagnostics.get("textured_materials", [])
	for required in ["body", "face", "hair", "iris", "cloth_primary", "cloth_secondary"]:
		_assert(required in textured, "missing textured material: %s" % required)
	for required_binding in ["body", "face", "hair", "iris", "cloth_primary", "cloth_secondary"]:
		_assert(required_binding in bindings.values(), "no visible mesh uses %s" % required_binding)
	_assert(not bindings.is_empty(), "Jue has no adapted LOD0 meshes")
	print("JUE_MATERIAL_CHECK_PASS meshes=%d textured=%s" % [bindings.size(), textured])
	room.queue_free()
	await process_frame
	quit(0)


## [C8.1] 失败时返回非零退出码并保留具体材质错误。
func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("JUE_MATERIAL_CHECK_FAIL: %s" % message)
	quit(1)
	assert(condition, message)
