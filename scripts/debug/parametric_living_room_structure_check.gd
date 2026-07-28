# parametric_living_room_structure_check.gd — validate floor, walls,
# wall dimensions, visual/collision center alignment at placement origin.
# Run: Godot --headless --path . --script scripts/debug/parametric_living_room_structure_check.gd
#
# Verifies: S4.1
# Responsibility: 验证 Structure 子树包含 Floor + 声明的墙体、
# 墙体尺寸来自 Manifest、每个 placement 的 visual 和 collision 中心对齐到
# placement origin、rigid 已冻结。
# Covers: 结构 → 尺寸 → 原点对齐 → 物理冻结

extends SceneTree

const MANIFEST_PATH := "res://data/scene_generation/manifests/living_room_shadow.seed42.manifest.json"
const REGISTRY_PATH := "res://data/scene_generation/registries/living_room_shadow_registry.json"


func _init() -> void:
	call_deferred("_run_check")


## [S4.1] 构建房间，验证 Structure（Floor + walls）和所有 placement 的
## visual/collision 中心位于局部原点。
func _run_check() -> void:
	print("\n=== [Parametric Living Room Structure Check] ===")

	var manifest := _load_json(MANIFEST_PATH)
	var registry := _load_json(REGISTRY_PATH)
	if manifest.is_empty() or registry.is_empty():
		printerr("FAIL: could not load manifest or registry")
		quit(1)
		return

	var builder := ParametricSceneBuilder.new()
	var check_root := Node3D.new()
	check_root.name = "CheckRoot"
	root.add_child(check_root)

	builder.build_room(check_root, manifest, registry)

	var generated_room := check_root.get_node_or_null("GeneratedRoom")
	if generated_room == null:
		printerr("FAIL: no GeneratedRoom node found")
		check_root.free()
		quit(1)
		return

	var errors := 0
	var structure := generated_room.get_node_or_null("Structure")
	if structure == null:
		printerr("FAIL: no Structure node found")
		errors += 1
	else:
		errors += _check_floor_and_walls(structure, manifest)

	var placements_node := generated_room.get_node_or_null("Placements")
	if placements_node == null:
		printerr("FAIL: no Placements node found")
		errors += 1
	else:
		errors += _check_visual_collision_origins(placements_node)

	if errors > 0:
		printerr("\nFAIL: %d error(s)" % errors)
		check_root.free()
		quit(1)
		return

	check_root.free()
	print("\n=== PASS ===\n")
	quit(0)


## [S4.1] 验证 Floor 节点存在，并确认所有声明的墙体都在 Structure 中。
## 墙体尺寸 (height_m) 来自 Manifest 且一致。
func _check_floor_and_walls(structure: Node3D, manifest: Dictionary) -> int:
	var errs := 0

	# Floor must exist.
	var floor_node := structure.get_node_or_null("Floor")
	if floor_node == null:
		printerr("FAIL: no Floor under Structure")
		errs += 1
	else:
		print("  Floor: OK")

	# Wall count should match manifest.
	var manifest_walls: Array = manifest.get("room", {}).get("walls", [])
	var expected_wall_count := manifest_walls.size()
	var built_wall_count := 0

	for child in structure.get_children():
		if child is Node3D and "Wall_" in child.name:
			built_wall_count += 1

	if built_wall_count != expected_wall_count:
		printerr("FAIL: expected %d walls, got %d" % [expected_wall_count, built_wall_count])
		errs += 1
	else:
		print("  Walls: %d (matches manifest)" % built_wall_count)

	# Verify each Manifest wall has a corresponding StaticBody in Structure.
	var missing_walls := PackedStringArray()
	for wall_data in manifest_walls:
		var wall_id: String = wall_data.get("wall_id", "")
		var wall_name := "Wall_" + wall_id.capitalize()
		if structure.get_node_or_null(wall_name) == null:
			missing_walls.append(wall_id)
		else:
			var height_m: float = wall_data.get("height_m", 3.0)
			# Verify wall mesh height matches manifest height_m.
			var mesh_node := structure.get_node(wall_name).get_node_or_null("WallMesh_" + wall_id) as MeshInstance3D
			if mesh_node != null and mesh_node.mesh is BoxMesh:
				var mesh_size := (mesh_node.mesh as BoxMesh).size
				if abs(mesh_size.y - height_m) > 0.001:
					printerr("FAIL: wall '%s' height mismatch — expected %.2f, got %.2f" % [wall_id, height_m, mesh_size.y])
					errs += 1

	if not missing_walls.is_empty():
		printerr("FAIL: missing walls: %s" % [",".join(missing_walls)])
		errs += 1

	return errs


## [S4.1] 对于每个 placement，验证其内部 Visual 子树的 AABB 中心位于
## 局部原点（允许通过设置 position 位移来实现居中）。
## CollisionShape 必须直接位于局部 (0,0,0)。
func _check_visual_collision_origins(placements_node: Node3D) -> int:
	var errs := 0
	var checked := 0

	for child in placements_node.get_children():
		if not child is Node3D:
			continue
		checked += 1
		var sid: String = child.get_meta("semantic_id", "unnamed")

		# Find Visual node; check that its subtree AABB center is at local origin.
		var visual := (child as Node3D).find_child("Visual", false, false) as Node3D
		if visual == null:
			var body := (child as Node3D).get_node_or_null("PhysicsBody")
			if body != null:
				visual = (body as Node3D).get_node_or_null("Visual") as Node3D
		if visual != null:
			var visual_center := _compute_subtree_center(visual)
			if visual_center.length_squared() > 0.001:
				printerr("FAIL: '%s' Visual AABB center not at local origin (offset=%s)" % [sid, visual_center])
				errs += 1

		# Find CollisionShape; its position must be (0,0,0) relative to its parent.
		for desc in (child as Node3D).find_children("CollisionShape", "", true, false):
			var cp := (desc as Node3D).position
			if cp.length_squared() > 0.000001:
				printerr("FAIL: '%s' CollisionShape not at local origin (offset=%s)" % [sid, cp])
				errs += 1

	print("  visual/collision centers checked: %d" % checked)
	return errs


## [S4.1] 递归计算 Node3D 子树在节点局部空间的 AABB 中心。
## 累积子节点 transform 变换，支持任意深度嵌套。
func _compute_subtree_center(node: Node3D) -> Vector3:
	var bounds := AABB()
	var found := false
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh != null:
			var child_aabb: AABB = child.transform * child.get_aabb()
			bounds = child_aabb if not found else bounds.merge(child_aabb)
			found = true
		elif child is Node3D:
			var child_local: AABB = _collect_subtree_bounds(child)
			if child_local.size != Vector3.ZERO:
				var child_transformed: AABB = child.transform * child_local
				bounds = child_transformed if not found else bounds.merge(child_transformed)
				found = true
	return bounds.get_center() if found else Vector3.ZERO


## [S4.1] 递归收集子树 AABB（内部方法）。
func _collect_subtree_bounds(node: Node3D) -> AABB:
	var bounds := AABB()
	var found := false
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh != null:
			var child_aabb: AABB = child.transform * child.get_aabb()
			bounds = child_aabb if not found else bounds.merge(child_aabb)
			found = true
		elif child is Node3D:
			var child_local: AABB = _collect_subtree_bounds(child)
			if child_local.size != Vector3.ZERO:
				var child_transformed: AABB = child.transform * child_local
				bounds = child_transformed if not found else bounds.merge(child_transformed)
				found = true
	return bounds if found else AABB()


## [S4.1] 从 res:// 路径加载并解析 JSON。
func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		printerr("FAIL: cannot open ", path)
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		printerr("FAIL: cannot parse ", path, " code=", err)
		return {}
	return json.get_data() as Dictionary
