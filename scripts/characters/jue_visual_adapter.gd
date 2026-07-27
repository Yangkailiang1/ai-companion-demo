# Roadmap: C8.1, C8.2
# Responsibility: 从 Git 忽略目录可选加载诀的本地 FBX，并绑定 LOD0 材质；
# 资产缺失时保留公开占位模型，不负责动作、表情选择或剧情调度。
# Collaborators: Jue local FBX scene, CharacterPoseOverlay
# Tests: scripts/debug/jue_material_check.gd

extends Node

const MODEL_PATH := (
	"res://assets/local_characters/jue/source/chr_0036_jsspsi_postmodel.fbx"
)
const TEXTURE_ROOT := "res://assets/local_characters/jue/textures/"

var _materials: Dictionary = {}
var _adapted_meshes: Dictionary = {}
var _is_local_model_loaded := false


## [C8.1][O4] 优先加载本地受限模型；公开检出缺失时保留占位角色。
func _ready() -> void:
	_is_local_model_loaded = _load_optional_model()
	if not _is_local_model_loaded:
		return
	_create_materials()
	call_deferred("_adapt")


## [C8.1][O4] 从 Git 忽略目录实例化诀；失败时不破坏 Agent 运行时。
func _load_optional_model() -> bool:
	if not ResourceLoader.exists(MODEL_PATH):
		return false
	var model_scene := load(MODEL_PATH) as PackedScene
	if model_scene == null:
		push_warning("JueVisualAdapter: local model could not load")
		return false
	var model := model_scene.instantiate()
	model.name = "JueModel"
	add_child(model)
	var placeholder := get_node_or_null("PublicPlaceholder") as Node3D
	if placeholder:
		placeholder.visible = false
	return true


## [C8.1] 从当前模型根递归绑定诀的材质；不修改共享导入资源。
func _adapt() -> void:
	_adapt_recursive(self)


## [C8.1] 遍历模型子树，将实际网格交给分区适配器。
func _adapt_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		_adapt_mesh(node as MeshInstance3D)
	for child in node.get_children():
		_adapt_recursive(child)


## [C8.1][C8.2] 隐藏代理/未适配特效，并按网格语义绑定贴图材质。
func _adapt_mesh(mesh_instance: MeshInstance3D) -> void:
	var mesh_name := String(mesh_instance.name).to_lower()
	if _should_hide_mesh(mesh_name):
		mesh_instance.visible = false
		return
	if not "_lod0" in mesh_name:
		return
	var material_id := _resolve_material_id(mesh_name)
	var material: StandardMaterial3D = _materials.get(material_id)
	if material == null:
		return
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mesh_instance.material_override = material
	_adapted_meshes[String(mesh_instance.name)] = material_id


## [C8.2] 判定当前 Demo 中需要隐藏的低 LOD、阴影代理和未完成布料特效。
func _should_hide_mesh(mesh_name: String) -> bool:
	if "shadowproxy" in mesh_name or "_lod1" in mesh_name or "_lod2" in mesh_name or "_lod3" in mesh_name:
		return true
	if "vfxpart" in mesh_name:
		return true
	for cloth_index in range(4, 10):
		if "cloth_%02d" % cloth_index in mesh_name:
			return true
	return false


## [C8.1] 将 FBX 网格名称映射到稳定材质区域。
func _resolve_material_id(mesh_name: String) -> String:
	if "face" in mesh_name or "eyeshadow" in mesh_name:
		return "face"
	if "body" in mesh_name:
		return "body"
	if "hair" in mesh_name or "brow" in mesh_name:
		return "hair"
	if "iris" in mesh_name or "eye" in mesh_name:
		return "iris"
	if "cloth_01" in mesh_name:
		return "cloth_primary"
	if "cloth_02" in mesh_name:
		return "cloth_secondary"
	if "cloth_03" in mesh_name:
		return "cloth_accent"
	return "cloth_accent"


## [C8.1] 用模型自带 D/N/E 贴图创建诀的身体、头发、眼睛和服装材质。
func _create_materials() -> void:
	_materials = {
		"body": _textured_material("T_actor_jsspsi_body_01_D.png", "T_actor_jsspsi_body_01_N.png", "", 0.78),
		"face": _textured_material("T_actor_jsspsi_face_01_D.png", "T_actor_jsspsi_face_01_N.png", "", 0.82),
		"hair": _textured_material("T_actor_jsspsi_hair_01_D.png", "T_actor_jsspsi_hair_01_HN.png", "", 0.72, true),
		"iris": _textured_material("T_actor_jsspsi_iris_01_D.png", "", "", 0.42, true),
		"cloth_primary": _textured_material("T_actor_jsspsi_cloth_01_D.png", "T_actor_jsspsi_cloth_01_N.png", "T_actor_jsspsi_cloth_01_E.png", 0.72),
		"cloth_secondary": _textured_material("T_actor_jsspsi_cloth_02_D.png", "T_actor_jsspsi_cloth_02_N.png", "T_actor_jsspsi_cloth_02_E.png", 0.76),
		"cloth_accent": _flat_material(Color(0.32, 0.28, 0.38, 1.0), 0.78),
	}


## [C8.1] 创建带可选法线、发光及透明裁切的 StandardMaterial3D。
func _textured_material(
	albedo_file: String,
	normal_file: String,
	emission_file: String,
	roughness: float,
	uses_alpha: bool = false
) -> StandardMaterial3D:
	var material := _flat_material(Color.WHITE, roughness)
	material.albedo_texture = _load_texture(albedo_file)
	if not normal_file.is_empty():
		material.normal_enabled = true
		material.normal_texture = _load_texture(normal_file)
	if not emission_file.is_empty():
		material.emission_enabled = true
		material.emission_texture = _load_texture(emission_file)
		material.emission = Color.WHITE
		material.emission_energy_multiplier = 0.35
	if uses_alpha:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.35
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## [C8.1] 创建无贴图的安全回退材质。
func _flat_material(albedo: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = roughness
	return material


## [C8.1] 加载已导入 Texture2D；缺失时发出明确诊断。
func _load_texture(filename: String) -> Texture2D:
	var path := TEXTURE_ROOT + filename
	var texture := load(path) as Texture2D
	if texture == null:
		push_warning("JueVisualAdapter: missing texture %s" % path)
	return texture


## [C8.1][X5.1] 返回不含图像数据的材质绑定诊断，供验收脚本读取。
func get_material_diagnostics() -> Dictionary:
	var textured_materials: Array[String] = []
	for material_id in _materials:
		var material: StandardMaterial3D = _materials[material_id]
		if material.albedo_texture != null:
			textured_materials.append(String(material_id))
	textured_materials.sort()
	return {
		"adapted_meshes": _adapted_meshes.duplicate(true),
		"textured_materials": textured_materials,
		"local_model_loaded": _is_local_model_loaded,
	}


## [C8.1][O4] 返回当前是否成功加载 Git 忽略目录中的本地诀模型。
func is_local_model_loaded() -> bool:
	return _is_local_model_loaded
