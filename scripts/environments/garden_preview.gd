extends Node3D

# The source scene contains three 32 m, unlit white helper planes. They cover the
# actual pavilion in Godot, so the preview hides them and uses its own neutral floor.
const SOURCE_HELPER_PLANES := ["平面_005", "平面_007", "平面_008"]


func _ready() -> void:
	for node_name in SOURCE_HELPER_PLANES:
		var helper := find_child(node_name, true, false) as GeometryInstance3D
		if helper:
			helper.visible = false
