# Roadmap: S4.1
# Responsibility: Summarize generated placement coverage and physics roles;
# does not create nodes, load assets or mutate a WorldLocation.
# Collaborators: ParametricSceneBuilder, ParametricAssetFactory
# Tests: scripts/debug/parametric_living_room_builder_check.gd

class_name ParametricBuildReporter
extends RefCounted


## [S4.1] 汇总临时 placement 容器中的模型覆盖与碰撞角色计数。
func summarize(placements_node: Node3D, placement_count: int) -> Dictionary:
	var counts := {
		"loaded": 0, "fallbacks": 0, "collisions": 0,
		"rigid": 0, "static": 0, "none": 0,
	}
	for child in placements_node.get_children():
		if not child is Node3D:
			continue
		var physics_role: String = child.get_meta("physics_role", "none")
		counts[physics_role if physics_role in ["rigid", "static"] else "none"] += 1
		if physics_role in ["rigid", "static"]:
			counts.collisions += 1
		if _has_loaded_model(child):
			counts.loaded += 1
		else:
			counts.fallbacks += 1
	counts["placements"] = placement_count
	return counts


## [S4.1] 检查子树是否包含非 BoxMesh 的真实外部模型。
func _has_loaded_model(node: Node3D) -> bool:
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh != null and not child.mesh is BoxMesh:
			return true
		if child is Node3D and _has_loaded_model(child):
			return true
	return false
