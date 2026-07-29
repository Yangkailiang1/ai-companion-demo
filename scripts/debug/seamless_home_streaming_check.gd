# Verifies: S2.5, P2.3, S3.3
# Covers: stitched room geometry, walk-through semantic switching without
# teleport, continuous floor collision, and a lightweight dynamic prop.

extends SceneTree

const EXPECTED_ROOMS := ["LivingRoom", "Kitchen", "Bedroom", "Study", "Sunroom"]

var _failed := false


## [S2.5] 延迟执行，等待 Autoload 和主场景进入树。
func _init() -> void:
	call_deferred("_run")


## [S2.5][P2.3][S3.3] 执行住宅连续空间纵向验收。
func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var loader := scene.get_node("WorldRoot") as WorldLocationLoader
	_assert(loader.switch_location("parametric") == "parametric", "parametric init")
	await _settle()
	_verify_all_rooms_resident(loader)
	await _verify_floor_continuity(loader)
	_verify_dynamic_pillow(loader)
	await _verify_walkthrough_without_teleport(loader)
	await _settle()
	scene.free()
	await process_frame
	if not _failed:
		print("SEAMLESS_HOME_STREAMING_PASS rooms=5 teleport=false floor=true pillow=true")
	quit(1 if _failed else 0)


## [S2.5] 五个房间必须同时存在且相邻门框占据同一个世界坐标。
func _verify_all_rooms_resident(loader: WorldLocationLoader) -> void:
	for room_name in EXPECTED_ROOMS:
		_assert(loader.get_node_or_null(room_name) != null, "missing room " + room_name)
	var living := loader.get_node_or_null("LivingRoom") as Node3D
	var kitchen := loader.get_node_or_null("Kitchen") as Node3D
	if living == null or kitchen == null:
		return
	var living_door := living.get_node_or_null("Portal_door_to_kitchen") as Node3D
	var kitchen_door := kitchen.get_node_or_null("Portal_door_to_living_kitchen") as Node3D
	_assert(living_door != null and kitchen_door != null, "paired doors missing")
	if living_door != null and kitchen_door != null:
		_assert(
			living_door.global_position.distance_to(kitchen_door.global_position) < 0.01,
			"paired doors are not aligned",
		)
	var study := loader.get_node_or_null("Study") as Node3D
	var sunroom := loader.get_node_or_null("Sunroom") as Node3D
	if study == null or sunroom == null:
		return
	var study_door := study.get_node_or_null("Portal_door_to_sunroom") as Node3D
	var sunroom_door := sunroom.get_node_or_null("Portal_door_to_study_sunroom") as Node3D
	_assert(study_door != null and sunroom_door != null, "sunroom paired doors missing")
	if study_door != null and sunroom_door != null:
		_assert(
			study_door.global_position.distance_to(sunroom_door.global_position) < 0.01,
			"sunroom paired doors are not aligned",
		)


## [S2.5][P2.3] 门槛两侧均须有可承载玩家的地板碰撞。
func _verify_floor_continuity(loader: WorldLocationLoader) -> void:
	var space := loader.get_world_3d().direct_space_state
	for x in [-4.35, -3.65]:
		var query := PhysicsRayQueryParameters3D.create(
			Vector3(x, 1.0, 0.9), Vector3(x, -0.4, 0.9)
		)
		var hit := space.intersect_ray(query)
		_assert(not hit.is_empty(), "floor gap beside kitchen threshold x=%.2f" % x)


## [S3.3] 靠枕必须是低质量、默认可运动的刚体，供玩家身体推动。
func _verify_dynamic_pillow(loader: WorldLocationLoader) -> void:
	var body := loader.get_node_or_null(
		"LivingRoom/FloorPillow/PhysicsBody"
	) as RigidBody3D
	_assert(body != null, "dynamic floor pillow missing")
	if body != null:
		_assert(not body.freeze, "floor pillow starts frozen")
		_assert(body.mass <= 0.5, "floor pillow too heavy to kick")


## [S2.5][P2.3] 身体穿门只改变活动语义房间，不能改写玩家世界坐标。
func _verify_walkthrough_without_teleport(loader: WorldLocationLoader) -> void:
	var living := loader.get_node_or_null("LivingRoom") as Node3D
	var portal := living.get_node_or_null("Portal_door_to_kitchen") if living != null else null
	var player := loader.get_node_or_null("PlayerBody") as PlayerFirstPersonController
	_assert(portal != null and player != null, "walkthrough actors missing")
	if portal == null or player == null:
		return
	player.global_position = Vector3(-3.48, 0.9, 0.9)
	await physics_frame
	await process_frame
	_assert(loader.current_location_id == "living_room", "approach switched room too early")
	var source_pivot := portal.get_node_or_null("Frame/DoorLeafPivot") as Node3D
	await create_timer(0.25).timeout
	_assert(
		source_pivot != null and source_pivot.rotation_degrees.y < -70.0,
		"approach sensor did not open door",
	)
	player.global_position = Vector3(-4.0, 0.9, 0.9)
	var before := player.global_position
	for _frame in range(4):
		await physics_frame
		await process_frame
	_assert(loader.current_location_id == "kitchen", "walkthrough did not activate kitchen")
	_assert(
		player.global_position.distance_to(before) < 1.0,
		"walkthrough teleported player",
	)
	await create_timer(0.3).timeout
	await process_frame
	var semantic := root.get_node_or_null("SemanticWorld")
	if semantic != null:
		_assert(
			String(semantic.get("active_location_id")) == "kitchen",
			"semantic location did not follow body",
		)
	var source_portal := living.get_node_or_null("Portal_door_to_kitchen") as Node3D
	var kitchen := loader.get_node_or_null("Kitchen") as Node3D
	var target_portal := (
		kitchen.get_node_or_null("Portal_door_to_living_kitchen") as Node3D
		if kitchen != null else null
	)
	_assert(source_portal != null and not source_portal.visible, "source door stayed active")
	_assert(target_portal != null and target_portal.visible, "arrival door not visible")
	if target_portal != null:
		var pivot := target_portal.get_node_or_null("Frame/DoorLeafPivot") as Node3D
		_assert(
			pivot != null and pivot.rotation_degrees.y < -70.0,
			"arrival door did not open",
		)


## [S2.5] 等待生成房间、导航与物理世界同步。
func _settle() -> void:
	for _frame in range(5):
		await physics_frame
		await process_frame


## [S2.5] 累积失败诊断。
func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("SEAMLESS_HOME_STREAMING_FAIL: " + message)
