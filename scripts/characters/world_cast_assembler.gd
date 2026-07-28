# Roadmap: S2.1, C6.2
# Responsibility: Instantiate the shared default cast directly under a
# WorldLocation; does not own room geometry, spawn policy or cognition state.
# Collaborators: main_agent.tscn, jue_agent.tscn, local_character_spawner.tscn
# Tests: scripts/debug/world_location_loader_check.gd

class_name WorldCastAssembler
extends RefCounted

const CAST_SCENES := [
	preload("res://scenes/characters/main_agent.tscn"),
	preload("res://scenes/characters/jue_agent.tscn"),
	preload("res://scenes/characters/local_character_spawner.tscn"),
]
const CAST_NODE_NAMES := ["Agent", "JueAgent", "LocalCharacterSpawner"]


## [S2.1][C6.2] 在地点根节点下实例化共享 Cast，保持既有公共 NodePath。
## 已存在同名节点时跳过，避免重复角色与重复认知信号连接。
func assemble_into(target: Node3D) -> Array[String]:
	var assembled: Array[String] = []
	for index in range(CAST_SCENES.size()):
		var node_name: String = CAST_NODE_NAMES[index]
		if target.has_node(node_name):
			continue
		var cast_node := (CAST_SCENES[index] as PackedScene).instantiate() as Node3D
		cast_node.name = node_name
		cast_node.set_meta("location_spawn_position", cast_node.position)
		cast_node.set_meta("location_spawn_rotation", cast_node.rotation)
		target.add_child(cast_node)
		assembled.append(node_name)
	return assembled
