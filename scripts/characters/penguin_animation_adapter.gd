class_name PenguinAnimationAdapter
extends Node

@export var idle_clip: String = "idle"
@export_range(-90.0, 0.0, 1.0) var idle_arm_drop_degrees: float = -52.0

var _applied := false
var _adjusted_tracks := 0


func _ready() -> void:
	var player := _find_animation_player(get_parent())
	if not player:
		push_warning("PenguinAnimationAdapter: AnimationPlayer not found")
		return
	_applied = _install_relaxed_idle(player)
	if not _applied:
		push_warning("PenguinAnimationAdapter: failed to install relaxed idle clip")


func is_relaxed_idle_applied() -> bool:
	return _applied


func get_adjusted_track_count() -> int:
	return _adjusted_tracks


func _install_relaxed_idle(player: AnimationPlayer) -> bool:
	var library_name := _find_library_for_clip(player, idle_clip)
	if library_name == &"__missing__":
		return false
	var source_library := player.get_animation_library(library_name)
	if not source_library:
		return false
	var local_library := source_library.duplicate(true) as AnimationLibrary
	if not local_library or not local_library.has_animation(idle_clip):
		return false
	var relaxed_idle := local_library.get_animation(idle_clip).duplicate(true) as Animation
	if not relaxed_idle:
		return false
	_adjusted_tracks = _drop_idle_arms(relaxed_idle)
	if _adjusted_tracks != 2:
		return false
	local_library.remove_animation(idle_clip)
	local_library.add_animation(idle_clip, relaxed_idle)
	player.remove_animation_library(library_name)
	player.add_animation_library(library_name, local_library)
	return true


func _drop_idle_arms(animation: Animation) -> int:
	var adjusted := 0
	var correction := Quaternion.from_euler(Vector3(deg_to_rad(idle_arm_drop_degrees), 0.0, 0.0))
	for track_index in range(animation.get_track_count()):
		if animation.track_get_type(track_index) != Animation.TYPE_ROTATION_3D:
			continue
		var path := String(animation.track_get_path(track_index))
		if not path.ends_with(":upper_arm.L") and not path.ends_with(":upper_arm.R"):
			continue
		for key_index in range(animation.track_get_key_count(track_index)):
			var value: Variant = animation.track_get_key_value(track_index, key_index)
			if value is Quaternion:
				animation.track_set_key_value(track_index, key_index, (value as Quaternion) * correction)
		adjusted += 1
	return adjusted


func _find_library_for_clip(player: AnimationPlayer, clip_name: String) -> StringName:
	for library_name in player.get_animation_library_list():
		var library := player.get_animation_library(library_name)
		if library and library.has_animation(clip_name):
			return library_name
	return &"__missing__"


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null
