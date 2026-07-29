# Roadmap: S4.1, O2.1
# Responsibility: Measure imported Poly Haven model bounds; do not alter assets or Registry.
# Tests: Run this script headlessly after Godot import.
#
# Run with:
# Godot --headless --log-file /private/tmp/ai_companion_polyhaven_bounds.log --path . --script scripts/debug/polyhaven_asset_bounds_check.gd

extends SceneTree


const ASSETS := {
	"Sofa_01": "res://assets/props/polyhaven/Sofa_01/Sofa_01_1k.gltf",
	"modern_coffee_table_01": "res://assets/props/polyhaven/modern_coffee_table_01/modern_coffee_table_01_1k.gltf",
	"Television_01": "res://assets/props/polyhaven/Television_01/Television_01_1k.gltf",
	"potted_plant_01": "res://assets/props/polyhaven/potted_plant_01/potted_plant_01_1k.gltf",
	"Shelf_01": "res://assets/props/polyhaven/Shelf_01/Shelf_01_1k.gltf",
	"modern_ceiling_lamp_01": "res://assets/props/polyhaven/modern_ceiling_lamp_01/modern_ceiling_lamp_01_1k.gltf",
	"hanging_picture_frame_01": "res://assets/props/polyhaven/hanging_picture_frame_01/hanging_picture_frame_01_1k.gltf",
	"woodentable_01": "res://assets/props/polyhaven/woodentable_01/WoodenTable_01_1k.gltf",
	"woodenchair_01": "res://assets/props/polyhaven/woodenchair_01/WoodenChair_01_1k.gltf",
	"ceramic_vase_01": "res://assets/props/polyhaven/ceramic_vase_01/ceramic_vase_01_1k.gltf",
}


## [S4.1][O2.1] 延迟到资源导入完成后执行只读测量。
func _init() -> void:
	call_deferred("_run")


## [S4.1][O2.1] 实例化每个模型并输出米制世界 AABB。
func _run() -> void:
	await process_frame
	for asset_name in ASSETS:
		var packed := load(ASSETS[asset_name]) as PackedScene
		if packed == null:
			push_error("POLYHAVEN_BOUNDS_FAIL: cannot load " + ASSETS[asset_name])
			quit(1)
			return
		var instance := packed.instantiate() as Node3D
		root.add_child(instance)
		await process_frame
		var bounds := _collect_bounds(instance)
		print("%s center=%s size=%s diag=%.3f" % [
			asset_name,
			bounds.get_center(),
			bounds.size,
			bounds.size.length(),
		])
		instance.free()
	print("POLYHAVEN_BOUNDS_PASS assets=%d" % ASSETS.size())
	quit(0)


## [S4.1][O2.1] 合并节点树内所有可见 MeshInstance3D 的世界边界。
func _collect_bounds(node: Node) -> AABB:
	var bounds := AABB()
	var has_bounds := false
	if node is MeshInstance3D and node.mesh != null:
		bounds = (node as MeshInstance3D).global_transform * (node as MeshInstance3D).get_aabb()
		has_bounds = true
	for child in node.get_children():
		var child_bounds := _collect_bounds(child)
		if child_bounds.size == Vector3.ZERO:
			continue
		if has_bounds:
			bounds = bounds.merge(child_bounds)
		else:
			bounds = child_bounds
			has_bounds = true
	return bounds if has_bounds else AABB()
