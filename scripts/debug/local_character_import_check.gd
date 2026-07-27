# Roadmap: C6.1, C6.2, C3.1, O4
# Responsibility: Validate an optional ignored local character GLB without
# making open-source checkouts depend on the restricted asset.
# Tests: Run with Godot --headless --path . --script <this file>.

extends SceneTree

const MODEL_PATH := "res://assets/local_characters/castorice/castorice.glb"


func _init() -> void:
	call_deferred("_run")


## [C6.1][C3.1][O4] 验证本地 GLB 的网格、骨骼和表情；缺失时安全跳过。
func _run() -> void:
	if not ResourceLoader.exists(MODEL_PATH):
		print("LOCAL_CHARACTER_IMPORT_SKIP path=%s" % MODEL_PATH)
		quit(0)
		return
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		_fail("local GLB is not a PackedScene")
		return
	var model := packed.instantiate()
	root.add_child(model)
	await process_frame
	var audit := {"meshes": 0, "textured": 0, "bones": 0, "morphs": []}
	_collect_model_data(model, audit)
	if int(audit.meshes) < 1 or int(audit.bones) < 20:
		_fail("incomplete model data: %s" % audit)
		return
	if int(audit.textured) < 1 or audit.morphs.is_empty():
		_fail("missing textures or morphs: %s" % audit)
		return
	print(
		"LOCAL_CHARACTER_IMPORT_PASS meshes=%d textured=%d bones=%d morphs=%d"
		% [audit.meshes, audit.textured, audit.bones, audit.morphs.size()]
	)
	quit(0)


## [C6.1][C3.1] 递归统计模型渲染、骨骼和 BlendShape 数据。
func _collect_model_data(node: Node, audit: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh:
		audit.meshes += 1
		if node.mesh.get_surface_count() > 0 and node.mesh.surface_get_material(0):
			audit.textured += 1
		for index in node.mesh.get_blend_shape_count():
			audit.morphs.append(String(node.mesh.get_blend_shape_name(index)))
	if node is Skeleton3D:
		audit.bones = maxi(int(audit.bones), node.get_bone_count())
	for child in node.get_children():
		_collect_model_data(child, audit)


func _fail(reason: String) -> void:
	push_error("LOCAL_CHARACTER_IMPORT_FAIL: %s" % reason)
	quit(1)
