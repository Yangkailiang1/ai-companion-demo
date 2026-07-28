# Roadmap: S4.1
# Responsibility: Thin preview controller — loads Manifest/Registry JSON,
# delegates building to ParametricSceneBuilder, and frames camera. Does not
# contain build logic, does not register with SemanticWorld, does not change
# startup scene or autoloads.
# Collaborators: ParametricSceneBuilder, ParametricAssetFactory
# Tests: scripts/debug/parametric_living_room_builder_check.gd

extends Node3D


## [S4.1] 加载 JSON manifest/registry 并调用 ParametricSceneBuilder 构建房间，
## 然后定位相机。
func _ready() -> void:
	var manifest: Dictionary = _load_json("res://data/scene_generation/manifests/living_room_shadow.seed42.manifest.json")
	var registry: Dictionary = _load_json("res://data/scene_generation/registries/living_room_shadow_registry.json")

	if manifest.is_empty() or registry.is_empty():
		printerr("ParametricLivingRoomPreview: failed to load manifest or registry")
		return

	var builder := ParametricSceneBuilder.new()
	var report: Dictionary = builder.build_room(self, manifest, registry)

	print("ParametricLivingRoomPreview built: ", report)
	_frame_camera()


## [S4.1] 从 res:// 路径解析 JSON 文件为 Dictionary。
func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		printerr("ParametricLivingRoomPreview: cannot open ", path)
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		printerr("ParametricLivingRoomPreview: parse error in ", path, " code=", err)
		return {}
	return json.get_data() as Dictionary


## [S4.1] 将相机定位到房间前方，给出概览视角。
func _frame_camera() -> void:
	var camera: Camera3D = get_node_or_null("Camera3D")
	if camera == null:
		return
	camera.global_position = Vector3(0.0, 5.5, 8.0)
	camera.look_at(Vector3(0.0, 1.2, -0.5), Vector3.UP)
	camera.fov = 45.0
