# Roadmap: S2.2, S2.5
# Responsibility: Build and animate one physical hinged door leaf. Does not
# detect travelers, resolve destinations or switch semantic locations.
# Collaborators: WorldTravelPortal
# Tests: scripts/debug/world_travel_portal_check.gd,
# scripts/debug/seamless_home_streaming_check.gd

class_name PhysicalDoorLeaf
extends Node3D

const CLOSED_DEGREES := 0.0
const OPEN_DEGREES := -96.0

var _body: AnimatableBody3D
var _tween: Tween


## [S2.2] 创建带 AnimatableBody3D 和盒碰撞的门扇，铰链位于门框左侧。
func configure(
	width: float,
	height: float,
	post_width: float,
	material: Material,
) -> void:
	name = "DoorLeafPivot"
	position = Vector3(-width * 0.5 + post_width, 0.0, 0.0)
	rotation_degrees.y = CLOSED_DEGREES
	_body = AnimatableBody3D.new()
	_body.name = "DoorLeafBody"
	_body.collision_layer = 1
	_body.collision_mask = 2
	add_child(_body)
	var leaf_size := Vector3(width * 0.88, height * 0.88, 0.07)
	var leaf_center := Vector3(leaf_size.x * 0.5, -0.04, 0.0)
	_add_mesh(leaf_size, leaf_center, material)
	var collision := CollisionShape3D.new()
	collision.name = "DoorLeafCollision"
	var shape := BoxShape3D.new()
	shape.size = leaf_size
	collision.shape = shape
	collision.position = leaf_center
	_body.add_child(collision)


## [S2.5] 非活动侧门停用碰撞，避免同一世界坐标的成对门重复阻挡。
func set_collision_active(active: bool) -> void:
	if _body == null:
		return
	_body.set_deferred("collision_layer", 1 if active else 0)
	_body.set_deferred("collision_mask", 2 if active else 0)


## [S2.2][S2.5] 快速开门、短暂停留后缓慢关闭。
func open_temporarily() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "rotation_degrees:y", OPEN_DEGREES, 0.22)
	_tween.tween_interval(1.15)
	_tween.set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "rotation_degrees:y", CLOSED_DEGREES, 0.42)


## [S2.2] 创建门扇视觉网格。
func _add_mesh(size: Vector3, center: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "DoorLeaf"
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = center
	mesh.set_surface_override_material(0, material)
	_body.add_child(mesh)
