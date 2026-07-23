extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var room: Node = load("res://scenes/living_room.tscn").instantiate()
	root.add_child(room)
	await process_frame
	await process_frame
	var player := _find_animation_player(room.get_node("Agent"))
	_assert(player != null, "penguin AnimationPlayer must exist")
	var idle := player.get_animation("idle")
	_assert(idle != null, "penguin idle clip must exist")
	for track_index in range(idle.get_track_count()):
		var path := String(idle.track_get_path(track_index))
		if "arm" not in path and "shoulder" not in path and "hand" not in path:
			continue
		var first_value: Variant = null
		if idle.track_get_key_count(track_index) > 0:
			first_value = idle.track_get_key_value(track_index, 0)
		print("PENGUIN_IDLE_TRACK index=%d type=%d path=%s keys=%d first=%s" % [
			track_index,
			idle.track_get_type(track_index),
			path,
			idle.track_get_key_count(track_index),
			first_value,
		])
	var skeleton := _find_skeleton(room.get_node("Agent"))
	_assert(skeleton != null, "penguin Skeleton3D must exist")
	_assert(_arm_direction(skeleton, "L").y < -0.5, "penguin left idle arm must point downward")
	_assert(_arm_direction(skeleton, "R").y < -0.5, "penguin right idle arm must point downward")
	_print_upper_arm_candidates(skeleton, "L")
	_print_upper_arm_candidates(skeleton, "R")
	room.queue_free()
	await process_frame
	print("PENGUIN_IDLE_CLIP_CHECK_PASS tracks=%d" % idle.get_track_count())
	quit(0)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null


func _arm_direction(skeleton: Skeleton3D, side: String) -> Vector3:
	var upper_index := skeleton.find_bone("upper_arm.%s" % side)
	var lower_index := skeleton.find_bone("lower_arm.%s" % side)
	var upper_origin := skeleton.get_bone_global_pose(upper_index).origin
	var lower_origin := skeleton.get_bone_global_pose(lower_index).origin
	return (lower_origin - upper_origin).normalized()


func _print_upper_arm_candidates(skeleton: Skeleton3D, side: String) -> void:
	var upper_index := skeleton.find_bone("upper_arm.%s" % side)
	var lower_index := skeleton.find_bone("lower_arm.%s" % side)
	var baseline := skeleton.get_bone_pose_rotation(upper_index)
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
		var delta := Quaternion.from_euler(degrees * PI / 180.0)
		skeleton.set_bone_pose_rotation(upper_index, baseline * delta)
		var upper_origin := skeleton.get_bone_global_pose(upper_index).origin
		var lower_origin := skeleton.get_bone_global_pose(lower_index).origin
		print("PENGUIN_ARM_CANDIDATE side=%s axis=%s direction=%s" % [
			side,
			label,
			(lower_origin - upper_origin).normalized(),
		])
	skeleton.set_bone_pose_rotation(upper_index, baseline)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("PENGUIN_IDLE_CLIP_CHECK_FAIL: %s" % message)
	quit(1)
	assert(condition, message)
