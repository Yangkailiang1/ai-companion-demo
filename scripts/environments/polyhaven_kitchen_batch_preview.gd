# Roadmap: S4.1, O2.1
# Responsibility: Frame the isolated Poly Haven kitchen batch for visual QA;
# do not modify Registry, production scenes, or asset transforms.
# Tests: scripts/debug/polyhaven_kitchen_batch_preview_check.gd

extends Node3D


## [S4.1][O2.1] Aim the preview camera at the shared asset center.
func _ready() -> void:
	var camera := get_node("Camera3D") as Camera3D
	camera.look_at(Vector3(0.0, 0.85, 0.0), Vector3.UP)
