# Roadmap: S2.2
# Responsibility: Read already-validated exit portal data and create
# WorldTravelPortal nodes under a room parent. Does NOT load the catalog,
# select target scenes, or modify SemanticWorld directly.
# Collaborators: WorldTravelPortal, ParametricRoomRuntime
# Tests: scripts/debug/world_travel_portal_check.gd

class_name WorldPortalAssembler
extends RefCounted

const WorldTravelPortalScript = preload("res://scripts/environments/world_travel_portal.gd")


## [S2.2] 遍历已校验的出口数据，为每个含 portal 块的出口创建入口节点。
## 副作用：在 room_parent 下实例化 WorldTravelPortal 并调用其 configure()。
## 返回创建的入口节点数组。
func assemble(
	room_parent: Node3D,
	exits: Dictionary,
	location_id: String,
) -> Array:
	var portals: Array = []
	for exit_id in exits:
		var exit_data = exits[exit_id]
		if not exit_data is Dictionary:
			continue
		var portal_block = exit_data.get("portal", {})
		if not portal_block is Dictionary or portal_block.is_empty():
			continue
		if not _validate_portal_block(portal_block):
			continue
		var portal := WorldTravelPortalScript.new()
		var configure_data: Dictionary = _build_configure_data(portal_block, exit_id, location_id)
		room_parent.add_child(portal)
		portal.configure(configure_data)
		portals.append(portal)
	return portals


## [S2.2] 校验 portal 块的必填字段与类型，不对目录做任何修改。
func _validate_portal_block(portal: Dictionary) -> bool:
	if not portal.has("semantic_id") or str(portal["semantic_id"]) == "":
		return false
	if not portal.has("label") or str(portal["label"]) == "":
		return false
	# 位置和尺寸必须为数值数组
	for field in ["position", "rotation_deg"]:
		var val = portal.get(field, [])
		if not val is Array or val.size() < 3:
			return false
		for v in val:
			if not v is float and not v is int:
				return false
	var size_val = portal.get("size", [])
	if not size_val is Array or size_val.size() < 2:
		return false
	for v in size_val:
		if not v is float and not v is int:
			return false
	return true


## [S2.2] 将 portal 块与出口元数据整合为 WorldTravelPortal 可用的配置字典。
func _build_configure_data(portal: Dictionary, exit_id: String, location_id: String) -> Dictionary:
	var data := portal.duplicate(true)
	data["exit_id"] = exit_id
	data["location_id"] = location_id
	return data
