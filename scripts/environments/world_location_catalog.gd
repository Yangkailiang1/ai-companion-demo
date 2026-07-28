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


## [S2.2] 从 JSON 装载地点图并进行最低限度结构校验。
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
	locations = parsed_locations.duplicate(true)
	default_location_id = String(parsed.get("default_location_id", ""))
	return locations.has(default_location_id)


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
