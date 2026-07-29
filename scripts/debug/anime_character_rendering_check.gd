# Verifies: C8.3, S1.2
# Covers: built-in + optional local character materials -> toon + outline;
# scene furniture remains PBR.

extends SceneTree

var failed := false


## [C8.3] Starts the asynchronous material contract.
func _init() -> void:
	call_deferred("_run")


## [C8.3][S1.2] Verifies all materialized character families and scene isolation.
func _run() -> void:
	var room := (load("res://scenes/living_room.tscn") as PackedScene).instantiate()
	root.add_child(room)
	for _frame in range(5):
		await process_frame
	var actors: Array[Node] = [
		room.get_node("Agent"),
		room.get_node("JueAgent"),
	]
	var spawner := room.get_node_or_null("LocalCharacterSpawner")
	if spawner != null:
		for child in spawner.get_children():
			if child is CharacterBody3D:
				actors.append(child)
	for actor in actors:
		_verify_actor(actor)
	_verify_scene_material_untouched(room)
	print("ANIME_CHARACTER_RENDERING_%s actors=%d" % [
		"FAIL" if failed else "PASS", actors.size(),
	])
	room.free()
	quit(1 if failed else 0)


## [C8.3] Checks one actor's adapter diagnostics and live surface materials.
func _verify_actor(actor: Node) -> void:
	var adapter := actor.get_node_or_null("AnimeRenderAdapter")
	_assert(adapter != null, "%s missing AnimeRenderAdapter" % actor.name)
	if adapter == null:
		return
	var diagnostics: Dictionary = adapter.get_render_diagnostics()
	_assert(String(diagnostics.get("profile", "")) == "anime_toon_v1",
		"%s uses wrong render profile" % actor.name)
	_assert(int(diagnostics.get("adapted_meshes", 0)) > 0,
		"%s has no toon mesh" % actor.name)
	_assert(int(diagnostics.get("adapted_surfaces", 0)) > 0,
		"%s has no toon surface" % actor.name)
	_assert(int(diagnostics.get("outlined_surfaces", 0)) > 0,
		"%s has no opaque outline" % actor.name)
	var material_counts := _count_live_materials(actor)
	_assert(int(material_counts.get("toon", 0)) > 0,
		"%s live materials are not toon" % actor.name)
	_assert(int(material_counts.get("outline", 0)) > 0,
		"%s live materials have no outline" % actor.name)


## [C8.3] Counts live toon and outline materials without inspecting texture data.
func _count_live_materials(actor: Node) -> Dictionary:
	var counts := {"toon": 0, "outline": 0}
	for child in actor.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var material := mesh_instance.get_active_material(surface_index)
			if not material is StandardMaterial3D:
				continue
			var standard := material as StandardMaterial3D
			if standard.diffuse_mode == BaseMaterial3D.DIFFUSE_TOON:
				counts["toon"] += 1
			var outline := standard.next_pass as ShaderMaterial
			if (
				outline != null
				and outline.shader != null
				and outline.shader.resource_path.ends_with("anime_outline.gdshader")
				and float(outline.get_shader_parameter("outline_width")) > 0.0
			):
				counts["outline"] += 1
	return counts


## [S1.2][C8.3] Ensures the character adapter never converts room furniture.
func _verify_scene_material_untouched(room: Node) -> void:
	var floor_mesh := room.get_node("Floor") as MeshInstance3D
	var floor_material := floor_mesh.get_active_material(0) as StandardMaterial3D
	_assert(floor_material != null, "room floor material missing")
	if floor_material != null:
		_assert(
			floor_material.diffuse_mode != BaseMaterial3D.DIFFUSE_TOON,
			"character toon adapter leaked into scene PBR materials",
		)


## [T4.2] Records a stable material-contract failure.
func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	failed = true
	push_error("ANIME_CHARACTER_RENDERING_FAIL: " + message)
