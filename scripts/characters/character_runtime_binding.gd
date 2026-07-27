# Roadmap: C6.2, C2.1, C3.1
# Responsibility: 从角色 manifest 注册模型专属动作/骨骼/表情适配合同；
# 不转换 PMX/VRM、不修改模型资源，也不播放剧情。
# Collaborators: CharacterAdapterRegistry, CharacterAnimationDriver, CharacterExpressionDriver
# Tests: scripts/debug/chibi_runtime_binding_check.gd

class_name CharacterRuntimeBinding
extends Node

@export_file("*.json") var manifest_path := ""

var _registered_agent_id := ""
var _last_error := ""


## [C6.2] 场景进入树时加载 manifest；空路径允许作为未配置模板存在。
func _ready() -> void:
	if not manifest_path.is_empty():
		register_manifest(manifest_path)


## [C6.2] 场景退出时撤销本角色的运行时适配器，避免幽灵 cast。
func _exit_tree() -> void:
	if not _registered_agent_id.is_empty() and has_node("/root/CharacterAdapterRegistry"):
		get_node("/root/CharacterAdapterRegistry").unregister_runtime_adapter(_registered_agent_id)
	_registered_agent_id = ""


## [C6.2][C2.1][C3.1] 读取 manifest 并注册动作、骨骼和表情适配合同。
## 失败时返回 false，注册表保持原状。
func register_manifest(path: String) -> bool:
	_last_error = ""
	if not FileAccess.file_exists(path):
		return _fail("角色 manifest 不存在: %s" % path)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return _fail("角色 manifest JSON 无效: %s" % path)
	if int(parsed.get("schema_version", 0)) != 1:
		return _fail("角色 manifest schema_version 必须为 1")
	var agent_id := String(parsed.get("agent_id", "")).strip_edges()
	var adapter: Dictionary = parsed.get("adapter", {})
	if not has_node("/root/CharacterAdapterRegistry"):
		return _fail("CharacterAdapterRegistry 不可用")
	var registry := get_node("/root/CharacterAdapterRegistry")
	if not registry.register_runtime_adapter(agent_id, adapter):
		return _fail(registry.get_last_error())
	_registered_agent_id = agent_id
	return true


## [C6.2][X5.1] 返回最近一次 manifest 注册错误；纯读取。
func get_last_error() -> String:
	return _last_error


## [C6.2] 记录安全错误并返回 false。
func _fail(reason: String) -> bool:
	_last_error = reason
	push_warning("CharacterRuntimeBinding: %s" % reason)
	return false
