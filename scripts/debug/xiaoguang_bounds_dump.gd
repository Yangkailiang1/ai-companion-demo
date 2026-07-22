# Dump runtime bounds for the Xiaoguang Yishi converted scene.
# Run with: Godot --headless --log-file /private/tmp/ai_companion_godot_bounds.log --path . --script scripts/debug/xiaoguang_bounds_dump.gd

extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var packed := load("res://scenes/environments/xiaoguang_yishi_preview.tscn") as PackedScene
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	for _frame in range(5):
		await process_frame
	var rows: Array[Dictionary] = []
	_collect(scene.find_child("XiaoguangModel", true, false), rows)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["diag"]) > float(b["diag"])
	)
	for index in range(mini(rows.size(), 32)):
		var row := rows[index]
		print("%02d name=%s diag=%.2f center=%s size=%s" % [
			index,
			row["name"],
			row["diag"],
			row["center"],
			row["size"],
		])
	scene.free()
	quit(0)


func _collect(node: Node, rows: Array[Dictionary]) -> void:
	if node == null:
		return
	if node is MeshInstance3D and node.mesh != null:
		var mesh_instance := node as MeshInstance3D
		var bounds := mesh_instance.global_transform * mesh_instance.get_aabb()
		rows.append({
			"name": mesh_instance.name,
			"diag": bounds.size.length(),
			"center": bounds.get_center(),
			"size": bounds.size,
		})
	for child in node.get_children():
		_collect(child, rows)
