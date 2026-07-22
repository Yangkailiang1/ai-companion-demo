extends Node3D


func _ready() -> void:
	_hide_preview_blockers()
	_frame_preview_camera()


func _hide_preview_blockers() -> void:
	# The source contains a very large helper/backdrop cube named "立方体" that
	# dominates the imported AABB and blocks the preview camera. Keep it out of
	# the Godot preview; the rest of the studio set remains visible.
	var model := find_child("XiaoguangModel", true, false)
	if model == null:
		return
	var blockers := ["立方体", "00A_天井", "006_北壁"]
	for blocker_name in blockers:
		var blocker := model.find_child(blocker_name, true, false)
		if blocker is Node3D:
			(blocker as Node3D).visible = false


func _frame_preview_camera() -> void:
	var camera := find_child("Camera3D", true, false) as Camera3D
	var model := find_child("XiaoguangModel", true, false)
	if camera == null or model == null:
		return
	var bounds := _collect_visible_bounds(model)
	if bounds.size == Vector3.ZERO:
		return
	var center := bounds.get_center()
	var size := bounds.size
	var radius := size.length() * 0.5
	var distance := maxf(radius * 1.85, 2.2)
	var height := maxf(size.y * 0.34, 0.72)
	camera.current = true
	camera.global_position = center + Vector3(distance * 0.12, height, -distance)
	camera.look_at(center + Vector3(0.0, size.y * 0.02, 0.0), Vector3.UP)
	camera.fov = 52.0
	camera.near = 0.05
	camera.far = maxf(distance * 6.0, 24.0)

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
