# Headless acceptance for the imported Xiaoguang Yishi preview scene.
# Run with: Godot --headless --path . --script scripts/debug/xiaoguang_scene_check.gd

extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var packed := load("res://scenes/environments/xiaoguang_yishi_preview.tscn") as PackedScene
	_assert(packed != null, "failed to load xiaoguang_yishi_preview.tscn")
	var scene := packed.instantiate()
	_assert(scene != null, "failed to instantiate xiaoguang preview")
	root.add_child(scene)
	current_scene = scene
	for _frame in range(5):
		await process_frame

	var stats := _collect_geometry_stats(scene.find_child("XiaoguangModel", true, false))
	_assert(stats["mesh_count"] >= 20, "mesh count is unexpectedly low: %d" % stats["mesh_count"])
	_assert(stats["visible_mesh_count"] >= 20, "visible mesh count is unexpectedly low: %d" % stats["visible_mesh_count"])
	_assert(stats["material_count"] >= 10, "material count is unexpectedly low: %d" % stats["material_count"])
	_assert(stats["aabb_diagonal"] > 0.5, "visible bounds are too small: %.2f" % stats["aabb_diagonal"])
	_assert(stats["aabb_diagonal"] < 10.0, "visible bounds are too large for preview scale: %.2f" % stats["aabb_diagonal"])
	_assert(scene.find_child("Camera3D", true, false) != null, "camera missing")
	_assert(scene.find_child("DirectionalLight3D", true, false) != null, "light missing")

	print("XIAOGUANG_SCENE_PASS meshes=%d visible=%d materials=%d diag=%.2f" % [
		stats["mesh_count"],
		stats["visible_mesh_count"],
		stats["material_count"],
		stats["aabb_diagonal"],
	])
	scene.free()
	quit(0)


func _collect_geometry_stats(node: Node) -> Dictionary:
	var stats := {
		"mesh_count": 0,
		"visible_mesh_count": 0,
		"material_count": 0,
		"aabb_diagonal": 0.0,
	}
	if node == null:
		return stats
	for child in node.get_children():
		var child_stats := _collect_geometry_stats(child)
		stats["mesh_count"] += child_stats["mesh_count"]
		stats["visible_mesh_count"] += child_stats["visible_mesh_count"]
		stats["material_count"] += child_stats["material_count"]
		stats["aabb_diagonal"] = maxf(stats["aabb_diagonal"], child_stats["aabb_diagonal"])
	if node is MeshInstance3D and node.mesh != null:
		var mesh_instance := node as MeshInstance3D
		stats["mesh_count"] += 1
		if mesh_instance.visible:
			stats["visible_mesh_count"] += 1
			stats["aabb_diagonal"] = maxf(stats["aabb_diagonal"], (mesh_instance.global_transform * mesh_instance.get_aabb()).size.length())
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			if mesh_instance.get_active_material(surface_index) != null:
				stats["material_count"] += 1
	return stats


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("XIAOGUANG_SCENE_FAIL: " + message)
	quit(1)
