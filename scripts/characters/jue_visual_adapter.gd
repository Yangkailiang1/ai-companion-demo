extends Node

var _skin_mat: StandardMaterial3D
var _hair_mat: StandardMaterial3D
var _cloth_dark_mat: StandardMaterial3D
var _cloth_light_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _fx_mat: StandardMaterial3D


func _ready() -> void:
	_create_materials()
	call_deferred("_adapt")


func _adapt() -> void:
	_adapt_recursive(self)


func _adapt_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		_adapt_mesh(node as MeshInstance3D)
	for child in node.get_children():
		_adapt_recursive(child)


func _adapt_mesh(mesh_instance: MeshInstance3D) -> void:
	var name := String(mesh_instance.name).to_lower()
	if "shadowproxy" in name or "_lod1" in name or "_lod2" in name or "_lod3" in name:
		mesh_instance.visible = false
		return
	if not "_lod0" in name:
		return
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if "face" in name or "body" in name:
		mesh_instance.material_override = _skin_mat
	elif "hair" in name or "brow" in name:
		mesh_instance.material_override = _hair_mat
	elif "iris" in name or "eye" in name:
		mesh_instance.material_override = _eye_mat
	elif "vfx" in name:
		mesh_instance.material_override = _fx_mat
	elif "cloth_01" in name or "cloth_02" in name or "cloth_03" in name or "cloth_07" in name or "cloth_08" in name:
		mesh_instance.material_override = _cloth_dark_mat
	else:
		mesh_instance.material_override = _cloth_light_mat


func _create_materials() -> void:
	_skin_mat = _mat(Color(0.93, 0.73, 0.65, 1), 0.82, Color(0.015, 0.01, 0.008, 1), 0.02)
	_hair_mat = _mat(Color(0.11, 0.09, 0.1, 1), 0.9, Color(0.01, 0.008, 0.01, 1), 0.015)
	_cloth_dark_mat = _mat(Color(0.2, 0.22, 0.28, 1), 0.92, Color(0.006, 0.008, 0.015, 1), 0.018)
	_cloth_light_mat = _mat(Color(0.72, 0.68, 0.62, 1), 0.92, Color(0.012, 0.01, 0.008, 1), 0.012)
	_eye_mat = _mat(Color(0.12, 0.16, 0.22, 1), 0.45, Color(0.04, 0.06, 0.08, 1), 0.1)
	_fx_mat = _mat(Color(0.45, 0.42, 0.52, 0.64), 0.86, Color(0.025, 0.02, 0.04, 1), 0.04)
	_fx_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _mat(albedo: Color, roughness: float, emission: Color, emission_energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = roughness
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = emission_energy
	return mat
