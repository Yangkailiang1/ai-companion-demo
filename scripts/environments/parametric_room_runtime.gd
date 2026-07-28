# Roadmap: S2.1, S4.1, C6.2
# Responsibility: Assemble one playable generated room and its shared cast;
# does not choose world mode or implement generation algorithms.
# Collaborators: ParametricSceneBuilder, WorldCastAssembler
# Tests: scripts/debug/world_location_loader_check.gd

extends Node3D

@export_file("*.json") var manifest_path := \
	"res://data/scene_generation/manifests/living_room_shadow.seed42.manifest.json"
@export_file("*.json") var registry_path := \
	"res://data/scene_generation/registries/living_room_shadow_registry.json"

var build_report: Dictionary = {}
var assembled_cast: Array[String] = []


## [S2.1][S4.1][C6.2] 构建房间后再迁移角色，保证角色入树时导航已存在。
func _ready() -> void:
	var manifest := _load_json(manifest_path)
	var registry := _load_json(registry_path)
	if manifest.is_empty() or registry.is_empty():
		push_error("ParametricRoomRuntime: manifest or registry unavailable")
		return
	build_report = ParametricSceneBuilder.new().build_room(self, manifest, registry)
	assembled_cast = WorldCastAssembler.new().assemble_into(self)
	call_deferred("_sync_navigation")


## [S4.1] 读取并解析项目内 JSON；失败返回空 Dictionary，不创建部分房间。
func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


## [S2.1][S4.2] 等待地点进入 World3D 后上传运行时 NavigationMesh 并强制同步。
## 生成网格在入树前逐多边形构造，不能依赖 Godot 的隐式上传时序。
func _sync_navigation() -> void:
	await get_tree().physics_frame
	_restore_location_spawns()
	var region := get_node_or_null(
		"GeneratedRoom/Structure/NavigationRegion3D"
	) as NavigationRegion3D
	if region == null or region.navigation_mesh == null:
		return
	NavigationServer3D.region_set_navigation_mesh(region.get_rid(), region.navigation_mesh)
	var map_rid := region.get_navigation_map()
	if map_rid != RID():
		NavigationServer3D.map_force_update(map_rid)


## [S2.1][X1] 在存档尚未包含 location_id 时恢复当前地点声明的出生点。
## 避免把 legacy 客厅坐标直接套到参数化布局；X1 v2 后由位置迁移器替代。
func _restore_location_spawns() -> void:
	for node_name in ["Agent", "JueAgent"]:
		var actor := get_node_or_null(node_name) as Node3D
		if actor == null or not actor.has_meta("location_spawn_position"):
			continue
		actor.position = actor.get_meta("location_spawn_position")
		actor.rotation = actor.get_meta("location_spawn_rotation")
