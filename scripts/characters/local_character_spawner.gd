# Roadmap: C6.1, C6.2, O4
# Responsibility: 从 Git 忽略的本地角色 manifest 安全生成可选角色；缺少受限资产时
# 静默跳过，确保开源仓库仍可独立运行。不转换模型、不选择剧情或动作。
# Collaborators: CharacterRuntimeBinding, AgentBase, CharacterAdapterRegistry
# Tests: scripts/debug/local_character_runtime_check.gd

extends Node3D

const CHARACTER_TEMPLATE := preload(
	"res://scenes/characters/local_runtime_character.tscn"
)

@export var manifest_paths: Array[String] = []


## [C6.1][O4] 延迟生成本地角色，使内置 Autoload 和场景导航先完成初始化。
func _ready() -> void:
	call_deferred("_spawn_available_characters")


## [C6.1][C6.2][O4] 逐个读取可选 manifest；缺失资产不产生破坏性错误。
func _spawn_available_characters() -> void:
	for manifest_path in manifest_paths:
		if not FileAccess.file_exists(manifest_path):
			continue
		var manifest := _read_manifest(manifest_path)
		if manifest.is_empty():
			continue
		var actor := _build_actor(manifest, manifest_path)
		if actor:
			add_child(actor)


## [C6.1][O4] 解析本地 manifest；无效输入返回空对象并保留主场景。
func _read_manifest(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_warning("LocalCharacterSpawner: invalid manifest %s" % path)
		return {}
	if int(parsed.get("schema_version", 0)) != 1:
		push_warning("LocalCharacterSpawner: unsupported schema in %s" % path)
		return {}
	return parsed


## [C6.1][C6.2] 根据模型、身份和出生点构建标准 Agent 节点树。
func _build_actor(manifest: Dictionary, manifest_path: String) -> CharacterBody3D:
	var model_path := String(manifest.get("model_scene", ""))
	var agent_id := String(manifest.get("agent_id", "")).strip_edges()
	if agent_id.is_empty() or not ResourceLoader.exists(model_path):
		push_warning("LocalCharacterSpawner: missing agent/model for %s" % manifest_path)
		return null
	var model_scene := load(model_path) as PackedScene
	if model_scene == null:
		return null
	var actor := CHARACTER_TEMPLATE.instantiate() as CharacterBody3D
	actor.name = String(manifest.get("node_name", agent_id))
	actor.agent_name = agent_id
	_configure_spawn(actor, manifest.get("spawn", {}))
	var model_root := actor.get_node("ModelRoot") as Node3D
	model_root.add_child(model_scene.instantiate())
	_configure_runtime_nodes(actor, agent_id, manifest_path, manifest)
	return actor


## [C6.1] 应用角色包的场景坐标、朝向、比例和碰撞范围。
func _configure_spawn(actor: CharacterBody3D, value: Variant) -> void:
	var spawn: Dictionary = value if value is Dictionary else {}
	actor.position = _vec3(spawn.get("position", [0, 0, 0]))
	actor.rotation_degrees = _vec3(spawn.get("rotation_degrees", [0, 0, 0]))
	var scale_value := float(spawn.get("model_scale", 1.0))
	(actor.get_node("ModelRoot") as Node3D).scale = Vector3.ONE * scale_value
	var collision := actor.get_node("AgentCollision") as CollisionShape3D
	collision.position.y = float(spawn.get("collision_height", 1.3)) * 0.5
	var shape := collision.shape as CapsuleShape3D
	shape.height = float(spawn.get("collision_height", 1.3))
	shape.radius = float(spawn.get("collision_radius", 0.32))


## [C6.2][C3.1] 给标准表现节点写入独立角色 ID、manifest 和标签。
func _configure_runtime_nodes(
	actor: CharacterBody3D,
	agent_id: String,
	manifest_path: String,
	manifest: Dictionary,
) -> void:
	actor.get_node("CharacterRuntimeBinding").manifest_path = manifest_path
	for node_name in [
		"CharacterAnimationDriver",
		"CharacterPoseOverlay",
		"CharacterExpressionDriver",
		"DialogueBubble",
	]:
		actor.get_node(node_name).agent_id = agent_id
	var display_name := String(
		manifest.get("display_name", manifest.get("adapter", {}).get("display_name", agent_id))
	)
	var spawn: Dictionary = manifest.get("spawn", {})
	var label := actor.get_node("AgentNameLabel") as Label3D
	label.text = display_name
	label.position.y = float(spawn.get("label_height", 1.55))
	(actor.get_node("DialogueBubble") as Sprite3D).position.y = (
		float(spawn.get("bubble_height", 1.75))
	)


func _vec3(value: Variant) -> Vector3:
	if not value is Array or value.size() < 3:
		return Vector3.ZERO
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
