# Roadmap: D2.2, S1.2, P2.1
# Responsibility: Convert validated story Beat focus into reusable observer-camera
# compositions; does not validate stories, move actors or take over first person.
# Collaborators: StoryDirector, MessageBus, OrbitRoomCamera, SemanticWorld
# Tests: scripts/debug/performance_camera_director_check.gd

extends Node

const MIN_DISTANCE := 3.4
const MAX_DISTANCE := 7.2
const BASE_EYE_HEIGHT := 0.9

var _story_active := false
var _last_shot_kind := ""
var _last_actor_id := ""
var _label_visibility: Dictionary = {}


## [D2.2] Connects the camera presentation layer to semantic story events.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	MessageBus.story_started.connect(_on_story_started)
	MessageBus.story_beat_started.connect(_on_story_beat_started)
	MessageBus.story_finished.connect(_on_story_finished)


## [D2.2] Marks a validated performance run active without moving the camera yet.
func _on_story_started(_story_id: String, _cast_ids: Array) -> void:
	_story_active = true
	_last_shot_kind = ""
	_last_actor_id = ""
	_hide_name_labels()


## [D2.2][P2.1] Builds a single/two-subject shot from the Beat's semantic focus.
## First person and cameras without the cinematic contract remain untouched.
func _on_story_beat_started(index: int, beat: Dictionary) -> void:
	if not _story_active:
		return
	var camera := _find_camera()
	if camera == null or not camera.has_method("begin_cinematic_shot"):
		return
	if camera.has_method("get_view_mode") and camera.get_view_mode() != "observer":
		return
	var actor_id := String(beat.get("actor", ""))
	var actor := _find_actor(actor_id)
	if actor == null:
		return
	var focus := _resolve_focus(beat)
	var composition := _compose_shot(camera, actor, focus, index)
	_last_actor_id = actor_id
	_last_shot_kind = String(composition["kind"])
	_set_cinematic_fill(camera, true)
	camera.begin_cinematic_shot(
		composition["position"],
		composition["target"],
		float(composition["fov"]),
	)


## [D2.2][P2.1] Smoothly restores the player's previous observer composition.
func _on_story_finished(_success: bool, _reason: String) -> void:
	_story_active = false
	_restore_name_labels()
	var camera := _find_camera()
	if camera != null and camera.has_method("end_cinematic_shot"):
		_set_cinematic_fill(camera, false)
		camera.end_cinematic_shot()


## [D2.2] Finds the current main camera without assuming a specific room node.
func _find_camera() -> Camera3D:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.find_child("Camera3D", true, false) as Camera3D


## [D2.2][C5] Resolves one agent by stable Agent ID rather than node name.
func _find_actor(agent_id: String) -> Node3D:
	for candidate in get_tree().get_nodes_in_group("agents"):
		if String(candidate.get("agent_name")) == agent_id:
			return candidate as Node3D
	return null


## [D2.2][T2.1] Resolves actor/object attention into a live world-space subject.
func _resolve_focus(beat: Dictionary) -> Node3D:
	if beat.has("look_at_actor"):
		return _find_actor(String(beat["look_at_actor"]))
	var object_id := ""
	if beat.has("look_at_object"):
		object_id = String(beat["look_at_object"])
	elif beat.get("interact") is Dictionary:
		object_id = String(beat["interact"].get("object", ""))
	if object_id.is_empty():
		return null
	var semantic_object = SemanticWorld.get_object(object_id)
	if semantic_object == null or not is_instance_valid(semantic_object.godot_node):
		return null
	return semantic_object.godot_node as Node3D


## [D2.2][S1.2] Creates a scale-aware composition using the current view side,
## avoiding hard-coded camera coordinates and alternating mild screen direction.
func _compose_shot(
	camera: Camera3D,
	actor: Node3D,
	focus: Node3D,
	beat_index: int,
) -> Dictionary:
	var actor_focus := actor.global_position + Vector3.UP * BASE_EYE_HEIGHT
	var target := actor_focus
	var subject_span := 0.0
	var kind := "single"
	if focus != null and focus != actor:
		var second_focus := focus.global_position + Vector3.UP * _focus_height(focus)
		target = (actor_focus + second_focus) * 0.5
		subject_span = actor_focus.distance_to(second_focus)
		kind = "two_subject"
	var view_out := camera.global_position - target
	view_out.y = 0.0
	if view_out.length_squared() < 0.01:
		view_out = Vector3.FORWARD
	else:
		view_out = view_out.normalized()
	var side := Vector3.UP.cross(view_out).normalized()
	var side_sign := -1.0 if beat_index % 2 == 0 else 1.0
	var distance := clampf(MIN_DISTANCE + subject_span * 0.7, MIN_DISTANCE, MAX_DISTANCE)
	var position := (
		target
		+ view_out * distance
		+ Vector3.UP * (1.0 + distance * 0.12)
		+ side * side_sign * minf(subject_span * 0.12, 0.38)
	)
	return {
		"position": position,
		"target": target,
		"fov": clampf(34.0 + subject_span * 1.8, 34.0, 44.0),
		"kind": kind,
	}


## [D2.2] Uses a lower focus point for props and an eye-height point for agents.
func _focus_height(node: Node3D) -> float:
	return BASE_EYE_HEIGHT if node.is_in_group("agents") else 0.45


## [D2.2][S1.2] Enables a soft camera-axis fill only during observer shots.
func _set_cinematic_fill(camera: Camera3D, enabled: bool) -> void:
	var fill := camera.get_node_or_null("CinematicFillLight") as SpotLight3D
	if fill != null:
		fill.visible = enabled


## [D2.2][S1.1] Hides world-space nameplates during close shots while keeping
## dialogue bubbles available; records exact prior visibility for restoration.
func _hide_name_labels() -> void:
	_label_visibility.clear()
	for actor in get_tree().get_nodes_in_group("agents"):
		var label := actor.get_node_or_null("AgentNameLabel") as Label3D
		if label == null:
			continue
		_label_visibility[label.get_instance_id()] = {
			"node": label,
			"visible": label.visible,
		}
		label.visible = false


## [D2.2][S1.1] Restores every still-live nameplate to its pre-story state.
func _restore_name_labels() -> void:
	for state in _label_visibility.values():
		var label = state.get("node")
		if is_instance_valid(label):
			label.visible = bool(state.get("visible", true))
	_label_visibility.clear()


## [D2.2][T4.2] Exposes non-sensitive camera direction diagnostics.
func get_diagnostics() -> Dictionary:
	return {
		"story_active": _story_active,
		"last_shot_kind": _last_shot_kind,
		"last_actor_id": _last_actor_id,
	}
