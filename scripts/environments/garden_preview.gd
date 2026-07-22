extends Node3D

# The source scene contains three 32 m, unlit white helper planes. They cover the
# actual pavilion in Godot, so the preview hides them and uses its own neutral floor.
const SOURCE_HELPER_PLANES := ["平面_005", "平面_007", "平面_008"]


func _ready() -> void:
	for node_name in SOURCE_HELPER_PLANES:
		var helper := find_child(node_name, true, false) as GeometryInstance3D
		if helper:
			helper.visible = false
	_frame_preview_camera()


func _frame_preview_camera() -> void:
	var camera := find_child("Camera3D", true, false) as Camera3D
	var garden_model := find_child("GardenModel", true, false)
	if camera == null or garden_model == null:
		return
	var bounds := _collect_visible_bounds(garden_model)
	if bounds.size == Vector3.ZERO:
		return
	var center := bounds.get_center()
	var size := bounds.size
	var distance := maxf(maxf(size.x, size.z) * 0.82, 12.0)
	var height := maxf(size.y * 0.55, 5.5)
	camera.global_position = center + Vector3(0.0, height, distance)
	camera.look_at(center + Vector3(0.0, size.y * 0.12, 0.0), Vector3.UP)
	camera.fov = 48.0
	camera.far = maxf(distance * 5.0, 120.0)

	var label := find_child("InfoLabel", true, false) as Label3D
	if label:
		label.global_position = center + Vector3(0.0, size.y + 1.2, 0.0)


func _collect_visible_bounds(node: Node) -> AABB:
	var bounds := AABB()
	var has_bounds := false
	if node is MeshInstance3D and node.visible and node.mesh != null:
		bounds = node.global_transform * node.get_aabb()
		has_bounds = true
	for child in node.get_children():
		var child_bounds := _collect_visible_bounds(child)
		if child_bounds.size == Vector3.ZERO:
			continue
		if has_bounds:
			bounds = bounds.merge(child_bounds)
		else:
			bounds = child_bounds
			has_bounds = true
	return bounds if has_bounds else AABB()
