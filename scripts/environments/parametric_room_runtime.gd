# Roadmap: S2.1, S4.1, C6.2
# Responsibility: Assemble one playable generated room and its transitional
# cast bridge; does not choose world mode or implement generation algorithms.
# Collaborators: ParametricSceneBuilder, LegacyCastExtractor
# Tests: scripts/debug/world_location_loader_check.gd

extends Node3D

@export_file("*.json") var manifest_path := \
	"res://data/scene_generation/manifests/living_room_shadow.seed42.manifest.json"
@export_file("*.json") var registry_path := \
	"res://data/scene_generation/registries/living_room_shadow_registry.json"

var build_report: Dictionary = {}
var extracted_cast: Array[String] = []


## [S2.1][S4.1][C6.2] 构建房间后再迁移角色，保证角色入树时导航已存在。
func _ready() -> void:
	var manifest := _load_json(manifest_path)
	var registry := _load_json(registry_path)
	if manifest.is_empty() or registry.is_empty():
		push_error("ParametricRoomRuntime: manifest or registry unavailable")
		return
	build_report = ParametricSceneBuilder.new().build_room(self, manifest, registry)
	extracted_cast = LegacyCastExtractor.new().extract_into(self)


## [S4.1] 读取并解析项目内 JSON；失败返回空 Dictionary，不创建部分房间。
func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}
