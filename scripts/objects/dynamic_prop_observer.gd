# Roadmap: S3.3, C9.5
# Responsibility: Observe one lightweight generated rigid prop and publish a
# semantic displacement event. Does not choose which character should react.
# Collaborators: ParametricAssetFactory, SemanticWorld, MessageBus
# Tests: scripts/debug/embodied_life_reaction_check.gd

extends Node

const ARM_DELAY_SECONDS := 1.0
const DISPLACEMENT_THRESHOLD_METERS := 0.32
const EVENT_COOLDOWN_SECONDS := 5.0

var object_id := ""
var _home_position := Vector3.ZERO
var _last_event_msec := -5000
var _armed := false


## [S3.3] 记录稳定物理物体身份，并在落地后建立“原位”基准。
func configure(semantic_id: String) -> void:
	object_id = semantic_id


## [S3.3] 等待刚体自然落地，避免把初次重力位移误判为玩家行为。
func _ready() -> void:
	await get_tree().create_timer(ARM_DELAY_SECONDS).timeout
	var body := get_parent() as RigidBody3D
	if body == null or not is_inside_tree():
		return
	_home_position = body.global_position
	_armed = true


## [S3.3][C9.5] 低频检测水平位移，并同步 AI 可见的实时空间位置。
func _physics_process(_delta: float) -> void:
	if not _armed:
		return
	var body := get_parent() as RigidBody3D
	if body == null:
		return
	_sync_semantic_position(body)
	var horizontal_offset := Vector2(
		body.global_position.x - _home_position.x,
		body.global_position.z - _home_position.z,
	).length()
	var now := Time.get_ticks_msec()
	if (
		horizontal_offset < DISPLACEMENT_THRESHOLD_METERS
		or now - _last_event_msec < int(EVENT_COOLDOWN_SECONDS * 1000.0)
	):
		return
	_last_event_msec = now
	SemanticWorld.update_object_state(object_id, "被碰离了原来的位置")
	MessageBus.world_state_changed.emit("dynamic_prop_displaced", {
		"object_id": object_id,
		"location_id": _location_id(),
		"home_position": _home_position,
		"position": body.global_position,
		"speed": body.linear_velocity.length(),
	})


## [S3.3] 刚体移动时更新语义对象坐标，保证 AI 导航到当前位置而非出生点。
func _sync_semantic_position(body: RigidBody3D) -> void:
	var object = SemanticWorld.get_object(object_id)
	if object == null:
		return
	object.position = body.global_position
	var anchor := body.get_node_or_null("AnchorApproach") as Marker3D
	object.interaction_point = (
		anchor.global_position if anchor != null else body.global_position
	)


## [S2.5][C9.5] 从参数化房间根读取稳定地点 ID。
func _location_id() -> String:
	var cursor := get_parent()
	while cursor != null:
		if cursor.has_meta("location_id"):
			return String(cursor.get_meta("location_id"))
		cursor = cursor.get_parent()
	return "living_room"
