extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var room: Node = load("res://scenes/living_room.tscn").instantiate()
	root.add_child(room)
	await process_frame
	await process_frame
	var skeleton := _find_skeleton(room.get_node("JueAgent")) as Skeleton3D
	_assert(skeleton != null, "Jue Skeleton3D must exist")
	var names := [
		"Bip001_L_Clavicle",
		"Bip001_L_UpperArm",
		"Bip001_L_Forearm",
		"Bip001_L_Hand",
		"Bip001_R_Clavicle",
		"Bip001_R_UpperArm",
		"Bip001_R_Forearm",
		"Bip001_R_Hand",
	]
	for bone_name in names:
		var index := skeleton.find_bone(bone_name)
		_assert(index >= 0, "missing bone %s" % bone_name)
		var rest := skeleton.get_bone_global_rest(index)
		var pose := skeleton.get_bone_global_pose(index)
		print("JUE_BONE_AXIS name=%s parent=%s rest_origin=%s pose_origin=%s local_pose_euler=%s" % [
			bone_name,
			skeleton.get_bone_name(skeleton.get_bone_parent(index)),
			rest.origin,
			pose.origin,
			skeleton.get_bone_pose_rotation(index).get_euler(),
		])
	var overlay := room.get_node_or_null("JueAgent/CharacterPoseOverlay")
	if overlay:
		overlay.enabled = false
	_print_upper_arm_candidates(skeleton, "L")
	_print_upper_arm_candidates(skeleton, "R")
	room.queue_free()
	await process_frame
	quit(0)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null


func _print_upper_arm_candidates(skeleton: Skeleton3D, side: String) -> void:
	var upper_index := skeleton.find_bone("Bip001_%s_UpperArm" % side)
	var forearm_index := skeleton.find_bone("Bip001_%s_Forearm" % side)
	var axes := {
		"base": Vector3.ZERO,
		"x+": Vector3(60, 0, 0),
		"x-": Vector3(-60, 0, 0),
		"y+": Vector3(0, 60, 0),
		"y-": Vector3(0, -60, 0),
		"z+": Vector3(0, 0, 60),
		"z-": Vector3(0, 0, -60),
	}
	for label in axes:
		var degrees: Vector3 = axes[label]
		skeleton.set_bone_pose_rotation(upper_index, Quaternion.from_euler(degrees * PI / 180.0))
		var upper_origin := skeleton.get_bone_global_pose(upper_index).origin
		var forearm_origin := skeleton.get_bone_global_pose(forearm_index).origin
		print("JUE_ARM_CANDIDATE side=%s axis=%s direction=%s" % [
			side,
			label,
			(forearm_origin - upper_origin).normalized(),
		])
	skeleton.set_bone_pose_rotation(upper_index, Quaternion.IDENTITY)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("JUE_SKELETON_AXIS_FAIL: %s" % message)
	quit(1)
	assert(condition, message)
