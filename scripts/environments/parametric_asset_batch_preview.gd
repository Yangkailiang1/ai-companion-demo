# Roadmap: S4.1
# Responsibility: 配置隔离资产批次预览相机；不修改 Registry 或生产场景。
# Tests: scripts/debug/parametric_asset_batch_preview_check.gd

extends Node3D


## [S4.1] 让预览相机稳定看向三件资产的共同中心。
func _ready() -> void:
	var camera := get_node("Camera3D") as Camera3D
	camera.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
