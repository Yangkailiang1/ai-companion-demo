# Roadmap: S2.1, C6.2
# Responsibility: Instantiate the shared default cast directly under a
# WorldLocation; does not own room geometry, spawn policy or cognition state.
# Collaborators: main_agent.tscn, jue_agent.tscn, local_character_spawner.tscn
# Tests: scripts/debug/world_location_loader_check.gd

class_name WorldCastAssembler
extends RefCounted

const CAST_SCENE_PATHS := [
	"res://scenes/characters/main_agent.tscn",
	"res://scenes/characters/jue_agent.tscn",
	"res://scenes/characters/local_character_spawner.tscn",
]
const CAST_NODE_NAMES := ["Agent", "JueAgent", "LocalCharacterSpawner"]


## [S2.1][C6.2] 在地点根节点下实例化共享 Cast，保持既有公共 NodePath。
## 已存在同名节点时跳过，避免重复角色与重复认知信号连接。
func assemble_into(
	target: Node3D,
	cast_members: Array = CAST_NODE_NAMES,
	local_character_manifests: Array = [],
) -> Array[String]:
	var assembled: Array[String] = []
	for index in range(CAST_SCENE_PATHS.size()):
		var node_name: String = CAST_NODE_NAMES[index]
		if node_name not in cast_members:
			continue
		if target.has_node(node_name):
			continue
		var packed := load(CAST_SCENE_PATHS[index]) as PackedScene
		if packed == null:
			push_warning("WorldCastAssembler: unavailable cast scene " + CAST_SCENE_PATHS[index])
			continue
		var cast_node := packed.instantiate() as Node3D
		cast_node.name = node_name
		if node_name == "LocalCharacterSpawner" and not local_character_manifests.is_empty():
			cast_node.set("manifest_paths", local_character_manifests)
			cast_node.set_meta(
				"residency_manifest_paths", local_character_manifests.duplicate()
			)
		cast_node.set_meta("location_spawn_position", cast_node.position)
		cast_node.set_meta("location_spawn_rotation", cast_node.rotation)
		target.add_child(cast_node)
		assembled.append(node_name)
	return assembled
