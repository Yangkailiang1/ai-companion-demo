# Validate manifest + registry placement/model/fallback/physics counts.
# Run: Godot --headless --path . --script scripts/debug/parametric_living_room_builder_check.gd
#
# Verifies: S4.1, S4.2
# Responsibility: 验证 ParametricSceneBuilder + ParametricAssetFactory 的
# 全部 Manifest placement 均由模型库加载、物理角色与 Registry 一致，
# 且每个碰撞物体完成 InteractableObject / SemanticWorld 绑定。
# Covers: manifest加载 → registry索引 → 工厂创建 → builder报告 → 位置验证

extends SceneTree

const MANIFEST_PATH := "res://data/scene_generation/manifests/living_room_shadow.seed42.manifest.json"
const REGISTRY_PATH := "res://data/scene_generation/registries/living_room_shadow_registry.json"


func _init() -> void:
	call_deferred("_run_check")


## [S4.1] 主检查流程：加载 manifest + registry，构建房间，计数并验证位置。
func _run_check() -> void:
	print("\n=== [Parametric Living Room Builder Check] ===")

	var manifest := _load_json(MANIFEST_PATH)
	var registry := _load_json(REGISTRY_PATH)
	if manifest.is_empty() or registry.is_empty():
		printerr("FAIL: could not load manifest or registry")
		quit(1)
		return

	var builder := ParametricSceneBuilder.new()
	var check_root := Node3D.new()
	check_root.name = "CheckRoot"
	root.add_child(check_root)  # SceneTree.root (Viewport) owns the node tree

	var report: Dictionary = builder.build_room(check_root, manifest, registry)

	var generated_room := check_root.get_node_or_null("GeneratedRoom")
	if generated_room == null:
		printerr("FAIL: no GeneratedRoom node found")
		check_root.free()
		quit(1)
		return

	var placements_node := generated_room.get_node_or_null("Placements")
	if placements_node == null:
		printerr("FAIL: no Placements node under GeneratedRoom")
		check_root.free()
		quit(1)
		return

	# Count placements and verify names.
	var seen_ids: Array[String] = []
	var placement_count := 0
	var loaded_count := 0
	var fallback_count := 0
	var collision_count := 0
	var rigid_count := 0
	var static_count := 0
	var none_count := 0

	for child in placements_node.get_children():
		if not child is Node3D:
			continue
		placement_count += 1
		var semantic_id: String = child.get_meta("semantic_id", "")
		if semantic_id.is_empty():
			printerr("FAIL: placement node missing semantic_id metadata")
			check_root.free()
			quit(1)
			return
		if semantic_id in seen_ids:
			printerr("FAIL: duplicate semantic_id '%s'" % semantic_id)
			check_root.free()
			quit(1)
			return
		seen_ids.append(semantic_id)

		# Determine physics role from metadata.
		var phys_role: String = child.get_meta("physics_role", "none")
		match phys_role:
			"static":
				static_count += 1
				collision_count += 1
			"rigid":
				rigid_count += 1
				collision_count += 1
			_:
				none_count += 1

		# Check for loaded model vs fallback.
		if _has_loaded_model(child):
			loaded_count += 1
		else:
			fallback_count += 1

	# Verify deterministic node name = semantic_id (not array order).
	for semantic_id in seen_ids:
		var node := placements_node.get_node_or_null(semantic_id)
		if node == null:
			printerr("FAIL: node name does not match semantic_id '%s'" % semantic_id)
			check_root.free()
			quit(1)
			return

	print("  placements=%d models=%d fallbacks=%d collisions=%d rigid=%d static=%d none=%d" % [
		placement_count, loaded_count, fallback_count, collision_count, rigid_count, static_count, none_count,
	])

	# Verify expected counts.
	var errors := 0
	var expected := _expected_counts(manifest, registry)
	if placement_count != int(expected.placements):
		printerr("FAIL: expected %d placements, got %d" % [expected.placements, placement_count])
		errors += 1
	if loaded_count != int(expected.placements):
		printerr("FAIL: expected %d models, got %d" % [expected.placements, loaded_count])
		errors += 1
	if fallback_count != 0:
		printerr("FAIL: expected 0 fallbacks, got %d" % fallback_count)
		errors += 1
	if collision_count != int(expected.collisions):
		printerr("FAIL: expected %d collisions, got %d" % [expected.collisions, collision_count])
		errors += 1
	if rigid_count != int(expected.rigid):
		printerr("FAIL: expected %d rigid, got %d" % [expected.rigid, rigid_count])
		errors += 1
	if static_count != int(expected.static):
		printerr("FAIL: expected %d static, got %d" % [expected.static, static_count])
		errors += 1
	if none_count != int(expected.none):
		printerr("FAIL: expected %d none, got %d" % [expected.none, none_count])
		errors += 1

	# Verify positions match manifest within 0.001 m.
	var manifest_placements: Array = manifest.get("placements", [])
	var manifest_lookup: Dictionary = {}
	for p in manifest_placements:
		var sid: String = p.get("semantic_id", "")
		if not sid.is_empty():
			manifest_lookup[sid] = p

	for child in placements_node.get_children():
		var sid: String = child.get_meta("semantic_id", "")
		var mp: Dictionary = manifest_lookup.get(sid, {})
		if mp.is_empty():
			printerr("FAIL: placement '%s' not found in manifest" % sid)
			errors += 1
			continue

		var expected_pos := _array_to_vector3(mp.get("position", [0.0, 0.0, 0.0]))
		var actual_pos := (child as Node3D).global_position
		var pos_delta := (actual_pos - expected_pos).abs()
		if pos_delta.x > 0.001 or pos_delta.y > 0.001 or pos_delta.z > 0.001:
			printerr("FAIL: '%s' position mismatch — expected %s, got %s (delta=%s)" % [
				sid, expected_pos, actual_pos, pos_delta,
			])
			errors += 1

		# Verify AnchorApproach exists and position matches interaction_point.
		var expected_ip := _array_to_vector3(mp.get("interaction_point", [0.0, 0.0, 0.0]))
		var anchor := (child as Node3D).find_child("AnchorApproach", true, false) as Marker3D
		if anchor == null:
			printerr("FAIL: '%s' missing AnchorApproach node" % sid)
			errors += 1
		else:
			var ip_delta := (anchor.global_position - expected_ip).abs()
			if ip_delta.x > 0.001 or ip_delta.y > 0.001 or ip_delta.z > 0.001:
				printerr("FAIL: '%s' interaction_point mismatch — expected %s, got %s (delta=%s)" % [
					sid, expected_ip, anchor.global_position, ip_delta,
				])
				errors += 1

		# Verify collision shape exists for non-none physics.
		var phys_role: String = child.get_meta("physics_role", "none")
		if phys_role != "none":
			var shapes_found := 0
			for desc in child.find_children("CollisionShape", "", true, false):
				shapes_found += 1
			if shapes_found == 0:
				printerr("FAIL: '%s' has physics '%s' but no CollisionShape" % [sid, phys_role])
				errors += 1

		# Verify none physics has no CollisionShape.
		if phys_role == "none":
			if child.find_children("CollisionShape", "", true, false).size() > 0:
				printerr("FAIL: '%s' has none physics but found CollisionShape" % sid)
				errors += 1

		# Verify PhysicsBody type matches.
		var body := (child as Node3D).get_node_or_null("PhysicsBody")
		match phys_role:
			"static":
				if body == null or not body is StaticBody3D:
					printerr("FAIL: '%s' expected StaticBody3D, got %s" % [sid, body.get_class() if body else "null"])
					errors += 1
			"rigid":
				if body == null or not body is RigidBody3D:
					printerr("FAIL: '%s' expected RigidBody3D, got %s" % [sid, body.get_class() if body else "null"])
					errors += 1
				elif not (body as RigidBody3D).freeze:
					printerr("FAIL: '%s' rigid body not frozen" % sid)
					errors += 1
			"none":
				if body != null:
					printerr("FAIL: '%s' has none physics but PhysicsBody exists" % sid)
					errors += 1
		var expected_semantic_node: Node3D = body if body != null else child
		var semantic_world := root.get_node("SemanticWorld")
		var semantic_object = semantic_world.get_object(sid)
		if semantic_object == null or semantic_object.godot_node != expected_semantic_node:
			printerr("FAIL: '%s' is not bound to SemanticWorld" % sid)
			errors += 1
		elif semantic_object.interaction_point.distance_to(expected_ip) > 0.001:
			printerr("FAIL: '%s' SemanticWorld interaction point mismatch" % sid)
			errors += 1
		if body != null:
			if not body.has_method("perform_interaction"):
				printerr("FAIL: '%s' physics body is not interactable" % sid)
				errors += 1

	if errors > 0:
		printerr("\nFAIL: %d error(s)" % errors)
		check_root.free()
		quit(1)
		return

	check_root.free()
	print("\n=== PASS ===\n")
	quit(0)


## [S4.2] 从 Manifest + Registry 推导物理计数，避免新增模型后测试写死数量。
func _expected_counts(manifest: Dictionary, registry: Dictionary) -> Dictionary:
	var roles := {}
	for asset in registry.get("assets", []):
		roles[String(asset.get("asset_id", ""))] = String(
			asset.get("roles", {}).get("physics", "none")
		)
	var result := {
		"placements": manifest.get("placements", []).size(),
		"collisions": 0,
		"rigid": 0,
		"static": 0,
		"none": 0,
	}
	for placement in manifest.get("placements", []):
		var role: String = roles.get(String(placement.get("asset_id", "")), "none")
		result[role] += 1
		if role != "none":
			result.collisions += 1
	return result


## [S4.1] 从 res:// 路径加载并解析 JSON，返回 Dictionary。
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


## [S4.1] 检查节点子树中是否存在非 BoxMesh 的 MeshInstance3D，指示加载的模型。
func _has_loaded_model(node: Node3D) -> bool:
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh != null:
			if not child.mesh is BoxMesh:
				return true
		if child is Node3D:
			if _has_loaded_model(child):
				return true
	return false


## [S4.1] 安全地将 Array 转换为 Vector3。
func _array_to_vector3(arr: Array) -> Vector3:
	if arr.size() < 3:
		return Vector3.ZERO
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
