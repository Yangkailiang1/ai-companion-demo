# Roadmap: S2.1, C6.2
# Responsibility: Extract the existing cast subtrees from the legacy room as a
# migration bridge; never copies cognition state or room geometry.
# Collaborators: living_room.tscn, LocalCharacterSpawner
# Tests: scripts/debug/world_location_loader_check.gd

class_name LegacyCastExtractor
extends RefCounted

const LEGACY_ROOM_PATH := "res://scenes/living_room.tscn"
const CAST_NODE_NAMES := ["Agent", "JueAgent", "LocalCharacterSpawner"]


## [S2.1][C6.2] 从未入树的旧房间实例中移出角色层并挂到新地点。
## 返回成功迁移的节点名；资源加载失败时返回空数组且不修改 target。
func extract_into(target: Node3D) -> Array[String]:
	var packed := load(LEGACY_ROOM_PATH) as PackedScene
	if packed == null:
		return []
	var legacy_room := packed.instantiate()
	var extracted: Array[String] = []
	for node_name in CAST_NODE_NAMES:
		var cast_node := legacy_room.get_node_or_null(node_name) as Node3D
		if cast_node == null:
			continue
		legacy_room.remove_child(cast_node)
		_clear_owner_recursive(cast_node)
		target.add_child(cast_node)
		extracted.append(node_name)
	legacy_room.free()
	return extracted


## [S2.1] 清除旧 PackedScene owner，避免迁移后的场景所有权不一致警告。
func _clear_owner_recursive(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_owner_recursive(child)
