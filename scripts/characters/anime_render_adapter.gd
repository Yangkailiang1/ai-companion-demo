# Roadmap: C8.3, S1.2
# Responsibility: Convert one character's imported StandardMaterial3D surfaces
# to toon lighting and scale-correct outlines while preserving their textures;
# does not alter scene props, geometry, skeletons, animation or expressions.
# Collaborators: Main/Jue/local character scenes, JueVisualAdapter
# Tests: scripts/debug/anime_character_rendering_check.gd

class_name AnimeRenderAdapter
extends Node

const OUTLINE_SHADER := preload("res://assets/shaders/anime_outline.gdshader")

@export var model_roots: Array[NodePath] = []
@export_range(0.002, 0.02, 0.001) var outline_width_m := 0.007
@export var outline_color := Color(0.055, 0.045, 0.075, 1.0)
@export_range(0.5, 1.0, 0.05) var minimum_roughness := 0.7
@export_range(0.0, 0.3, 0.05) var maximum_metallic := 0.1

var _adapted_mesh_count := 0
var _adapted_surface_count := 0
var _outlined_surface_count := 0
var _skipped_surface_count := 0


## [C8.3][T4.2] Queues adaptation after optional local model/material setup.
func _ready() -> void:
	call_deferred("apply_now")


## [C8.3] Reapplies the toon profile to declared model roots.
## Side effects: installs per-instance surface overrides; shared imports remain unchanged.
func apply_now() -> void:
	_reset_diagnostics()
	for root_path in model_roots:
		var model_root := get_node_or_null(root_path)
		if model_root != null:
			_adapt_recursive(model_root)


## [C8.3] Traverses only the character model subtree.
func _adapt_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		_adapt_mesh(node as MeshInstance3D)
	for child in node.get_children():
		_adapt_recursive(child)


## [C8.3] Converts active StandardMaterial3D surfaces without mutating Mesh data.
func _adapt_mesh(mesh_instance: MeshInstance3D) -> void:
	if mesh_instance.mesh == null or not mesh_instance.visible:
		return
	var surface_count := mesh_instance.mesh.get_surface_count()
	if surface_count <= 0:
		return
	var active_materials: Array[Material] = []
	for surface_index in range(surface_count):
		active_materials.append(mesh_instance.get_active_material(surface_index))
	mesh_instance.material_override = null
	var adapted_any := false
	for surface_index in range(surface_count):
		var source := active_materials[surface_index]
		if not source is StandardMaterial3D:
			_skipped_surface_count += 1
			continue
		var toon := _create_toon_material(
			source as StandardMaterial3D, mesh_instance
		)
		mesh_instance.set_surface_override_material(surface_index, toon)
		_adapted_surface_count += 1
		adapted_any = true
	if adapted_any:
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_adapted_mesh_count += 1


## [C8.3] Duplicates a source material, retaining textures/alpha while changing
## only its lighting model and optional next-pass outline.
func _create_toon_material(
	source: StandardMaterial3D,
	mesh_instance: MeshInstance3D,
) -> StandardMaterial3D:
	var toon := source.duplicate(true) as StandardMaterial3D
	toon.resource_local_to_scene = true
	toon.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	toon.specular_mode = BaseMaterial3D.SPECULAR_TOON
	toon.roughness = maxf(toon.roughness, minimum_roughness)
	toon.metallic = minf(toon.metallic, maximum_metallic)
	toon.next_pass = _create_outline_material(mesh_instance, toon)
	_outlined_surface_count += 1
	return toon


## [C8.3] Creates a front-face-culled expanded shell. The local grow amount is
## divided by global scale so Jue's centimeter FBX and Q models share line width.
func _create_outline_material(
	mesh_instance: MeshInstance3D,
	source: StandardMaterial3D,
) -> ShaderMaterial:
	var outline := ShaderMaterial.new()
	outline.resource_local_to_scene = true
	outline.shader = OUTLINE_SHADER
	var scale := mesh_instance.global_transform.basis.get_scale().abs()
	var average_scale := maxf((scale.x + scale.y + scale.z) / 3.0, 0.001)
	outline.set_shader_parameter("outline_color", outline_color)
	if source.albedo_texture != null:
		outline.set_shader_parameter("alpha_texture", source.albedo_texture)
		outline.set_shader_parameter("use_alpha_texture", true)
	outline.set_shader_parameter(
		"outline_width",
		clampf(outline_width_m / average_scale, 0.00001, 0.03),
	)
	return outline


## [C8.3][X5.1] Returns counts only; never exposes local texture data.
func get_render_diagnostics() -> Dictionary:
	return {
		"adapted_meshes": _adapted_mesh_count,
		"adapted_surfaces": _adapted_surface_count,
		"outlined_surfaces": _outlined_surface_count,
		"skipped_surfaces": _skipped_surface_count,
		"profile": "anime_toon_v1",
	}


## [C8.3] Clears counters before a deterministic reapply.
func _reset_diagnostics() -> void:
	_adapted_mesh_count = 0
	_adapted_surface_count = 0
	_outlined_surface_count = 0
	_skipped_surface_count = 0
