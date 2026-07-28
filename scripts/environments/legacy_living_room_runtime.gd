# Roadmap: S2.1, C6.2
# Responsibility: Replace serialized legacy cast nodes with the shared Cast
# scenes before children enter the tree; does not alter authored room geometry.
# Collaborators: WorldCastAssembler, living_room.tscn
# Tests: scripts/debug/world_location_loader_check.gd

extends Node3D

const LEGACY_CAST_NAMES := ["Agent", "JueAgent", "LocalCharacterSpawner"]


## [S2.1][C6.2] 在旧角色连接 Runtime 信号前移除历史节点并挂载共享场景。
## 序列化节点暂留作可回滚迁移数据，但运行时只有一套角色实例。
func _enter_tree() -> void:
	for node_name in LEGACY_CAST_NAMES:
		var legacy_node := get_node_or_null(node_name)
		if legacy_node == null:
			continue
		remove_child(legacy_node)
		legacy_node.free()
	WorldCastAssembler.new().assemble_into(self)
