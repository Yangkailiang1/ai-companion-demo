# Subtle idle breathing layer for the visible character model.
#
# This sits above imported skeletal animations, so even weak/flat idle clips read
# as a living character in static screenshots and while waiting for player input.

extends Node3D


@export var bob_amount: float = 0.018
@export var sway_amount: float = 0.035
@export var breathing_speed: float = 1.65

var _base_position := Vector3.ZERO
var _base_rotation := Vector3.ZERO
var _time := 0.0


func _ready() -> void:
	_base_position = position
	_base_rotation = rotation


func _process(delta: float) -> void:
	_time += delta * breathing_speed
	var breath := sin(_time)
	var soft_sway := sin(_time * 0.47)
	position = _base_position + Vector3(0.0, breath * bob_amount, 0.0)
	rotation = _base_rotation + Vector3(0.0, soft_sway * sway_amount, 0.0)
