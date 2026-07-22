# Headless acceptance for the imported endless garden preview scene.
# Run with: Godot --headless --path . --script scripts/debug/garden_scene_check.gd

extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var packed := load("res://scenes/environments/endless_garden_preview.tscn") as PackedScene
	_assert(packed != null, "failed to load endless_garden_preview.tscn")
	var scene := packed.instantiate()
	_assert(scene != null, "failed to instantiate endless garden preview")
	root.add_child(scene)
	current_scene = scene
	for _frame in range(5):
		await process_frame

	var camera := scene.find_child("Camera3D", true, false) as Camera3D
	var light := scene.find_child("DirectionalLight3D", true, false) as DirectionalLight3D
	var environment := scene.find_child("WorldEnvironment", true, false) as WorldEnvironment
	var garden_model := scene.find_child("GardenModel", true, false)
	_assert(camera != null, "preview camera is missing")
	_assert(light != null, "preview light is missing")
	_assert(environment != null and environment.environment != null, "world environment is missing")
	_assert(garden_model != null, "GardenModel instance is missing")

	var stats := _collect_geometry_stats(garden_model)
	_assert(stats["mesh_count"] >= 10, "garden mesh count is unexpectedly low: %d" % stats["mesh_count"])
	_assert(stats["visible_mesh_count"] >= 8, "garden visible mesh count is unexpectedly low: %d" % stats["visible_mesh_count"])
	_assert(stats["material_count"] >= 4, "garden material count is unexpectedly low: %d" % stats["material_count"])
	_assert(stats["aabb_diagonal"] > 5.0, "garden bounds are too small: %.2f" % stats["aabb_diagonal"])
	_assert(stats["aabb_diagonal"] < 80.0, "garden bounds are too large for preview scale: %.2f" % stats["aabb_diagonal"])

	var hidden_helpers := 0
	for helper_name in ["平面_005", "平面_007", "平面_008"]:
		var helper := scene.find_child(helper_name, true, false) as GeometryInstance3D
		if helper != null and not helper.visible:
			hidden_helpers += 1
	_assert(hidden_helpers >= 1, "expected at least one source helper plane to be hidden")

	print("GARDEN_SCENE_PASS meshes=%d visible=%d materials=%d diag=%.2f alpha=%d" % [
		stats["mesh_count"],
		stats["visible_mesh_count"],
		stats["material_count"],
		stats["aabb_diagonal"],
		stats["alpha_material_count"],
	])
	scene.free()
	quit(0)


func _collect_geometry_stats(node: Node) -> Dictionary:
	var stats := {
		"mesh_count": 0,
		"visible_mesh_count": 0,
		"material_count": 0,
		"alpha_material_count": 0,
		"aabb_diagonal": 0.0,
	}
	var bounds_initialized := false
	var bounds := AABB()
	for child in node.get_children():
		var child_stats := _collect_geometry_stats(child)
		stats["mesh_count"] += child_stats["mesh_count"]
		stats["visible_mesh_count"] += child_stats["visible_mesh_count"]
		stats["material_count"] += child_stats["material_count"]
		stats["alpha_material_count"] += child_stats["alpha_material_count"]
		stats["aabb_diagonal"] = maxf(stats["aabb_diagonal"], child_stats["aabb_diagonal"])

	if node is MeshInstance3D and node.mesh != null:
		var mesh_instance := node as MeshInstance3D
		stats["mesh_count"] += 1
		if mesh_instance.visible:
			stats["visible_mesh_count"] += 1
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var material := mesh_instance.get_active_material(surface_index)
			if material != null:
				stats["material_count"] += 1
				if material is BaseMaterial3D and (material as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					stats["alpha_material_count"] += 1
		bounds = mesh_instance.global_transform * mesh_instance.get_aabb()
		bounds_initialized = true

	if bounds_initialized:
		stats["aabb_diagonal"] = maxf(stats["aabb_diagonal"], bounds.size.length())
	return stats


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("GARDEN_SCENE_FAIL: " + message)
	quit(1)
