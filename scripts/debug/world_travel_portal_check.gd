# Verifies: S2.2
# Covers: visible portal contract -> six traversals -> stale guard -> strict
# catalog validation without publishing partial state.

extends SceneTree

const EXPECTED_KITCHEN_ENTRY := Vector3(0.0, 0.9, 2.15)

var _failed := false
var _temporary_paths: Array[String] = []


## [S2.2] 延迟执行，等待 Autoload 与主场景进入树。
func _init() -> void:
	call_deferred("_run")


## [S2.2] 执行可见入口、旅行链和目录 fail-closed 纵向验收。
func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var loader := scene.get_node("WorldRoot") as WorldLocationLoader
	_assert(loader.switch_location("parametric") == "parametric", "parametric init")
	await _settle()
	var living := loader.get_active_location()
	var kitchen := _verify_living_portals(living)
	var bedroom := _find_portal(living, "Portal_door_to_bedroom")
	if kitchen != null and bedroom != null:
		await _verify_six_traversals(loader, kitchen, bedroom)
	_verify_malformed_catalogs()
	_cleanup_temporary_files()
	scene.free()
	await process_frame
	if not _failed:
		print("WORLD_TRAVEL_PORTAL_PASS locations=4 traversals=6")
	quit(1 if _failed else 0)


## [S2.2] 验证客厅恰有两个具备渲染、碰撞、标签和语义能力的入口。
func _verify_living_portals(room: Node3D) -> Node:
	_assert(room != null, "living room missing")
	if room == null:
		return null
	var portals := _find_portals(room)
	_assert(portals.size() == 2, "living portal count=%d" % portals.size())
	var kitchen := _find_portal(room, "Portal_door_to_kitchen")
	var bedroom := _find_portal(room, "Portal_door_to_bedroom")
	_verify_portal_contract(kitchen, "door_to_kitchen", "厨房")
	_verify_portal_contract(bedroom, "door_to_bedroom", "卧室")
	return kitchen


## [S2.2] 验证单个入口不泄漏目标，只公开稳定 exit_id 与 traverse 合同。
func _verify_portal_contract(portal: Node, semantic_id: String, label: String) -> void:
	_assert(portal != null, "portal missing: " + semantic_id)
	if portal == null:
		return
	var descendants := _all_children(portal)
	_assert(_contains_type(descendants, "MeshInstance3D"), semantic_id + " mesh")
	_assert(_contains_type(descendants, "CollisionShape3D"), semantic_id + " collision")
	var label_node := portal.get_node_or_null("PortalLabel") as Label3D
	_assert(label_node != null and label_node.text == label, semantic_id + " label")
	_assert(portal.has_signal("travel_requested"), semantic_id + " signal")
	var semantic := root.get_node("SemanticWorld")
	_assert(semantic.can_interact(semantic_id, "traverse"), semantic_id + " semantic")
	var names := _property_names(portal)
	_assert(not names.has("target_location_id"), semantic_id + " leaked target")
	_assert(not names.has("scene_path"), semantic_id + " leaked scene")
	_assert(not portal.has_meta("target_location_id"), semantic_id + " target metadata")


## [S2.2] 经厨房、卧室、书房完成六次旅行并验证陈旧入口。
func _verify_six_traversals(loader: WorldLocationLoader, kitchen: Node, sibling: Node) -> void:
	var invalid: Dictionary = kitchen.perform_interaction("sit", "")
	_assert(not bool(invalid.get("handled", true)), "invalid verb handled")
	var first: Dictionary = kitchen.perform_interaction("traverse", "")
	_assert(bool(first.get("success", false)), "kitchen traverse rejected")
	var repeated: Dictionary = kitchen.perform_interaction("traverse", "")
	var stale_sibling: Dictionary = sibling.perform_interaction("traverse", "")
	_assert(not bool(repeated.get("success", false)), "double traverse accepted")
	_assert(not bool(stale_sibling.get("success", false)), "retired sibling accepted")
	await _settle()
	_assert(loader.current_location_id == "kitchen", "kitchen travel")
	_verify_player_entry(loader, EXPECTED_KITCHEN_ENTRY)
	await _traverse_only_portal(loader, "living_room")
	var bedroom := _find_portal(loader.get_active_location(), "Portal_door_to_bedroom")
	_assert(bedroom != null, "fresh bedroom portal missing")
	if bedroom == null:
		return
	bedroom.perform_interaction("traverse", "")
	await _settle()
	_assert(loader.current_location_id == "bedroom", "bedroom travel")
	var study := _find_portal(loader.get_active_location(), "Portal_door_to_study")
	_assert(study != null, "study portal missing")
	if study != null:
		study.perform_interaction("traverse", "")
		await _settle()
		_assert(loader.current_location_id == "study", "study travel")
		await _traverse_only_portal(loader, "bedroom")
	await _traverse_only_portal(loader, "living_room")


## [S2.2] 激活当前房间唯一入口并检查目标地点。
func _traverse_only_portal(loader: WorldLocationLoader, expected_location: String) -> void:
	var portals := _find_portals(loader.get_active_location())
	var selected: Node = null
	var location := loader.get_location_catalog().get_location(loader.current_location_id)
	for exit_id in location.get("exits", {}):
		var edge: Dictionary = location.exits[exit_id]
		if String(edge.get("target_location_id", "")) != expected_location:
			continue
		var semantic_id := String(edge.get("portal", {}).get("semantic_id", ""))
		selected = _find_portal(
			loader.get_active_location(), "Portal_" + semantic_id
		)
		break
	_assert(selected != null, "portal to %s expected" % expected_location)
	if selected == null:
		return
	selected.perform_interaction("traverse", "")
	await _settle()
	_assert(loader.current_location_id == expected_location, "expected " + expected_location)


## [S2.2][P2.3] 验证旅行入口只定位持久 PlayerBody。
func _verify_player_entry(loader: WorldLocationLoader, expected: Vector3) -> void:
	var player := loader.get_node_or_null("PlayerBody") as Node3D
	_assert(player != null, "PlayerBody missing after travel")
	if player != null:
		_assert(player.position.distance_to(expected) < 0.05, "wrong kitchen entry")


## [S2.2] 验证各类非法入口目录被拒绝且新目录不发布部分状态。
func _verify_malformed_catalogs() -> void:
	for kind in [
		"missing_portal", "missing_semantic_id", "bad_semantic_id",
		"missing_label", "missing_display_name", "bad_position",
		"bad_size", "duplicate_ids",
	]:
		var catalog := WorldLocationCatalog.new()
		var path := _write_fixture(kind)
		_assert(not catalog.load_catalog(path), "catalog accepted " + kind)
		_assert(catalog.locations.is_empty(), "partial catalog published: " + kind)
	var stable := WorldLocationCatalog.new()
	_assert(stable.load_catalog(), "valid catalog rejected")
	var original_size := stable.locations.size()
	_assert(not stable.load_catalog(_write_fixture("bad_size")), "bad reload accepted")
	_assert(stable.locations.size() == original_size, "valid catalog lost after bad reload")


## [S2.2] 写入一种不合法入口目录并返回临时路径。
func _write_fixture(kind: String) -> String:
	var base := _fixture_base()
	var portal: Dictionary = base.locations.test_loc.exits.to_test.portal
	match kind:
		"missing_portal": base.locations.test_loc.exits.to_test.portal = {}
		"missing_semantic_id": portal.erase("semantic_id")
		"bad_semantic_id": portal.semantic_id = "Door Test"
		"missing_label": portal.erase("label")
		"missing_display_name": portal.erase("display_name")
		"bad_position": portal.position = [0.0, 0.0]
		"bad_size": portal.size = [1.0, "bad"]
		"duplicate_ids":
			base.locations.test_loc2 = base.locations.test_loc.duplicate(true)
	var path := "/private/tmp/ai_companion_portal_%s.json" % kind
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(base))
	file.close()
	_temporary_paths.append(path)
	return path


## [S2.2] 返回合法的最小目录夹具；调用方只修改待测字段。
func _fixture_base() -> Dictionary:
	return {
		"schema_version": 1, "default_location_id": "test_loc",
		"locations": {"test_loc": {
			"entries": {"default": {"position": [0.0, 0.0, 0.0]}},
			"exits": {"to_test": {
				"target_location_id": "test_loc", "target_entry_id": "default",
				"portal": {
					"semantic_id": "door_test", "display_name": "测试门",
					"label": "测试", "position": [0.0, 1.0, 0.0],
					"rotation_deg": [0.0, 0.0, 0.0], "size": [1.0, 2.0],
				},
			}},
		}},
	}


## [S2.2] 查找房间直属的全部入口节点。
func _find_portals(room: Node3D) -> Array[Node]:
	var result: Array[Node] = []
	if room == null:
		return result
	for child in room.get_children():
		if String(child.name).begins_with("Portal_"):
			result.append(child)
	return result


## [S2.2] 按稳定节点名查找入口。
func _find_portal(room: Node3D, node_name: String) -> Node:
	return room.get_node_or_null(node_name) if room != null else null


## [S2.2] 返回节点所有递归后代。
func _all_children(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in node.get_children():
		result.append(child)
		result.append_array(_all_children(child))
	return result


## [S2.2] 检查节点数组是否含指定 Godot 类型。
func _contains_type(nodes: Array[Node], type_name: String) -> bool:
	for node in nodes:
		if node.is_class(type_name):
			return true
	return false


## [S2.2] 返回对象公开属性名。
func _property_names(object: Object) -> Array[String]:
	var result: Array[String] = []
	for item in object.get_property_list():
		result.append(String(item.get("name", "")))
	return result


## [S2.2] 等待房间构建、语义注册与退役宽限期完成。
func _settle() -> void:
	for _frame in range(4):
		await physics_frame
		await process_frame


## [S2.2] 删除本测试写入的临时目录文件。
func _cleanup_temporary_files() -> void:
	for path in _temporary_paths:
		DirAccess.remove_absolute(path)


## [S2.2] 累积失败诊断。
func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("WORLD_TRAVEL_PORTAL_FAIL: " + message)
