extends SceneTree

const LOCAL_MODEL_PATH := (
	"res://assets/local_characters/jue/source/chr_0036_jsspsi_postmodel.fbx"
)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ResourceLoader.exists(LOCAL_MODEL_PATH):
		print("JUE_IMPORT_CHECK_PASS local_asset=absent public_checkout=ready")
		quit(0)
		return
	var scene: PackedScene = load(LOCAL_MODEL_PATH)
	_assert(scene != null, "Jue FBX must load as PackedScene")
	var inst := scene.instantiate()
	root.add_child(inst)
	await process_frame
	var summary := {
		"meshes": 0,
		"armatures": 0,
		"animation_players": 0,
		"animations": [],
		"morphs": [],
		"bounds": AABB(),
		"has_bounds": false,
	}
	_collect(inst, summary)
	_assert(int(summary["meshes"]) > 0, "Jue import must contain meshes")
	print("JUE_IMPORT_CHECK_PASS meshes=%d anim_players=%d animations=%s morphs=%d bounds=%s" % [
		summary["meshes"],
		summary["animation_players"],
		str(summary["animations"]),
		summary["morphs"].size(),
		str(summary["bounds"]),
	])
	inst.queue_free()
	await process_frame
	quit(0)


func _collect(node: Node, summary: Dictionary) -> void:
	if node is MeshInstance3D:
		summary["meshes"] += 1
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh:
			var mesh_aabb := mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
			if not summary["has_bounds"]:
				summary["bounds"] = mesh_aabb
				summary["has_bounds"] = true
			else:
				summary["bounds"] = (summary["bounds"] as AABB).merge(mesh_aabb)
			var array_mesh := mesh_instance.mesh as ArrayMesh
			if array_mesh:
				for index in range(array_mesh.get_blend_shape_count()):
					summary["morphs"].append(String(array_mesh.get_blend_shape_name(index)))
	if node is Skeleton3D:
		summary["armatures"] += 1
	if node is AnimationPlayer:
		summary["animation_players"] += 1
		var player := node as AnimationPlayer
		for animation_name in player.get_animation_list():
			summary["animations"].append(String(animation_name))
	for child in node.get_children():
		_collect(child, summary)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("JUE_IMPORT_CHECK_FAIL: %s" % message)
	quit(1)
	assert(condition, message)
