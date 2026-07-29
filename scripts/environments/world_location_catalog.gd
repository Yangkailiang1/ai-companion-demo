# Roadmap: S2.2, S4.3
# Responsibility: Read and query the declarative home location graph; does not
# instantiate scenes, move actors or generate room geometry.
# Collaborators: WorldLocationLoader, data/world_locations.json
# Tests: scripts/debug/multi_room_home_check.gd

class_name WorldLocationCatalog
extends RefCounted

const DEFAULT_PATH := "res://data/world_locations.json"

var default_location_id := ""
var locations: Dictionary = {}
var initial_agent_locations: Dictionary = {}
var player_companion_ids: Array = []
var local_character_manifests: Dictionary = {}


## [S2.2] 从 JSON 装载地点图并进行结构/入口一致性/入口块校验。
## 入口块不合法（缺少语义 ID、位置/旋转非向量、尺寸无效、标签缺失或语义 ID 重复）
## 时 fail-closed：不发布部分目录。
func load_catalog(path: String = DEFAULT_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1:
		return false
	var parsed_locations = parsed.get("locations", {})
	if not parsed_locations is Dictionary or parsed_locations.is_empty():
		return false
	var candidate_locations: Dictionary = parsed_locations.duplicate(true)
	var candidate_default := String(parsed.get("default_location_id", ""))
	if not candidate_locations.has(candidate_default):
		return false
	if not _validate_portals(candidate_locations):
		return false
	var candidate_residency = parsed.get("agent_residency", {})
	var candidate_companions = parsed.get("player_companion_ids", [])
	var candidate_manifests = parsed.get("local_character_manifests", {})
	if (
		not candidate_residency is Dictionary
		or not candidate_companions is Array
		or not candidate_manifests is Dictionary
		or not _validate_residency(candidate_residency, candidate_locations)
	):
		return false
	locations = candidate_locations
	default_location_id = candidate_default
	initial_agent_locations = candidate_residency.duplicate(true)
	player_companion_ids = candidate_companions.duplicate()
	local_character_manifests = candidate_manifests.duplicate(true)
	return true


## [S2.2] 拒绝未知居民地点，避免角色永久无法实体化。
func _validate_residency(
	residency: Dictionary,
	candidate_locations: Dictionary,
) -> bool:
	for agent_id in residency:
		if String(agent_id).is_empty():
			return false
		if not candidate_locations.has(String(residency[agent_id])):
			return false
	return true


## [S2.2] 返回地点声明的深拷贝，防止调用方修改目录。
func get_location(location_id: String) -> Dictionary:
	var location = locations.get(location_id, {})
	return location.duplicate(true) if location is Dictionary else {}


## [S2.2] 判断地点是否存在；纯函数。
func has_location(location_id: String) -> bool:
	return locations.has(location_id)


## [S2.2] 解析某地点的具名出口；不存在时返回空字典。
func get_exit(location_id: String, exit_id: String) -> Dictionary:
	var location := get_location(location_id)
	var exits = location.get("exits", {})
	if not exits is Dictionary:
		return {}
	var exit_data = exits.get(exit_id, {})
	return exit_data.duplicate(true) if exit_data is Dictionary else {}


## [S2.2] 验证出口目标及目标入口同时存在，避免半条旅行边。
func can_travel(location_id: String, exit_id: String) -> bool:
	var edge := get_exit(location_id, exit_id)
	var target_id := String(edge.get("target_location_id", ""))
	var target := get_location(target_id)
	if target.is_empty():
		return false
	var entry_id := String(edge.get("target_entry_id", "default"))
	var entries = target.get("entries", {})
	return entries is Dictionary and entries.has(entry_id)


## [S2.2] 校验所有地点的 portal 块；任何非法块均返回 false。
## 检查项：缺少 semantic_id/label、position/rotation_deg 非三维数值数组、size 非二维
## 数值数组、语义 ID 跨所有地点重复。
func _validate_portals(candidate_locations: Dictionary) -> bool:
	var seen_ids: Array[String] = []
	for loc_id in candidate_locations:
		var location = candidate_locations[loc_id]
		if not location is Dictionary or not location.get("exits", {}) is Dictionary:
			return false
		var exits: Dictionary = location.get("exits", {})
		for exit_id in exits:
			if not exits[exit_id] is Dictionary:
				return false
			var portal = exits[exit_id].get("portal", {})
			if not portal is Dictionary or not _validate_portal_block(
				portal, String(loc_id), String(exit_id), seen_ids
			):
				return false
	return true


## [S2.2] 校验单个入口表现块并登记跨目录唯一的语义 ID。
func _validate_portal_block(
	portal: Dictionary,
	location_id: String,
	exit_id: String,
	seen_ids: Array[String],
) -> bool:
	var prefix := "WorldLocationCatalog: portal %s/%s " % [location_id, exit_id]
	var sid := String(portal.get("semantic_id", ""))
	if not _is_snake_case_id(sid):
		push_error(prefix + "semantic_id must be stable snake_case")
		return false
	if sid in seen_ids:
		push_error("WorldLocationCatalog: duplicate portal semantic_id '%s'" % sid)
		return false
	seen_ids.append(sid)
	for field in ["label", "display_name"]:
		if String(portal.get(field, "")).is_empty():
			push_error(prefix + "missing " + field)
			return false
	for field in ["position", "rotation_deg"]:
		if not _is_vec3_array(portal.get(field)):
			push_error(prefix + field + " must be a 3-number array")
			return false
	var size_value = portal.get("size", [])
	if not size_value is Array or size_value.size() != 2:
		push_error(prefix + "size must be a 2-number array")
		return false
	for component in size_value:
		if (not component is float and not component is int) or float(component) <= 0.0:
			push_error(prefix + "size must contain positive numbers")
			return false
	return true


## [S2.2] 检查值是否为恰好三个数值元素的数组；纯函数。
func _is_vec3_array(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for v in value:
		if not v is float and not v is int:
			return false
	return true


## [S2.2] 检查稳定语义 ID 是否为小写 snake_case；纯函数。
func _is_snake_case_id(value: String) -> bool:
	if value.is_empty() or value.to_snake_case() != value:
		return false
	var first := value.unicode_at(0)
	return first >= 97 and first <= 122
