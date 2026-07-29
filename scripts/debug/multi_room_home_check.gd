# Verifies: S2.2, S4.3, C6.2
# Covers: declarative graph -> kitchen/bedroom build -> active semantics -> cast
# spawn -> navigation -> safe invalid travel.

extends SceneTree

var _failed := false


## [S2.2] 延迟执行，等待主场景和 Autoload 完成初始化。
func _init() -> void:
	call_deferred("_run")


## [S2.2][S4.3] 验证住宅五地点的完整旅行纵切片。
func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var loader := scene.get_node("WorldRoot") as WorldLocationLoader
	_assert(loader.switch_location("parametric") == "parametric", "living room load failed")
	await _settle()
	_check_room(
		loader, "living_room", "LivingRoom", 17, "sofa", 2,
		["Agent", "JueAgent", "LocalCharacterSpawner"],
	)
	_assert(loader.travel_via("to_kitchen"), "living -> kitchen edge failed")
	await _settle()
	_check_room(loader, "kitchen", "Kitchen", 9, "kitchen_fridge", 1, ["Agent"])
	var kitchen_cup := loader.get_active_location().get_node_or_null(
		"KitchenCup/PhysicsBody"
	) as RigidBody3D
	_assert(
		kitchen_cup != null and kitchen_cup.freeze,
		"kitchen portable cup is not a ready rigid body",
	)
	_assert(not _visible_semantic_ids().has("sofa"), "kitchen sees living-room sofa")
	_assert(loader.travel_via("to_living"), "kitchen -> living edge failed")
	await _settle()
	_assert(loader.travel_via("to_bedroom"), "living -> bedroom edge failed")
	await _settle()
	_check_room(loader, "bedroom", "Bedroom", 7, "bed", 2, ["Agent"])
	_assert(not _visible_semantic_ids().has("kitchen_fridge"), "bedroom sees kitchen fridge")
	_assert(loader.travel_via("to_study"), "bedroom -> study edge failed")
	await _settle()
	_check_room(loader, "study", "Study", 6, "study_bookshelf", 2, ["Agent"])
	var study_book := loader.get_active_location().get_node_or_null(
		"StudyBook/PhysicsBody"
	) as RigidBody3D
	_assert(
		study_book != null and study_book.freeze,
		"study book is not a ready rigid body",
	)
	_assert(loader.travel_via("to_sunroom"), "study -> sunroom edge failed")
	await _settle()
	_check_room(
		loader, "sunroom", "Sunroom", 10, "sunroom_plant_main", 1, ["Agent"],
	)
	var watering_can := loader.get_active_location().get_node_or_null(
		"SunroomWateringCan/PhysicsBody"
	) as RigidBody3D
	var sunroom_pillow := loader.get_active_location().get_node_or_null(
		"SunroomPillow/PhysicsBody"
	) as RigidBody3D
	_assert(
		watering_can != null and watering_can.freeze,
		"sunroom watering can is not a ready rigid body",
	)
	_assert(
		sunroom_pillow != null and not sunroom_pillow.freeze,
		"sunroom pillow is not dynamic",
	)
	_check_sunroom_state(loader.get_active_location())
	_assert(loader.travel_via("to_study"), "sunroom -> study edge failed")
	await _settle()
	_assert(loader.current_location_id == "study", "sunroom return target wrong")
	var active_before := loader.get_active_location()
	_assert(not loader.travel_to("missing_room"), "invalid travel unexpectedly succeeded")
	_assert(loader.get_active_location() == active_before, "invalid travel replaced active room")
	scene.free()
	await process_frame
	print("MULTI_ROOM_HOME_%s" % ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)


## [S2.2][S4.3][C6.2] 检查生成覆盖、共享 Cast、语义域、导航网格和入口数量。
func _check_room(
	loader: WorldLocationLoader,
	location_id: String,
	root_name: String,
	placement_count: int,
	required_object_id: String,
	portal_count: int = 0,
	expected_cast: Array[String] = [],
) -> void:
	_assert(loader.current_location_id == location_id, "wrong current location: " + location_id)
	var room := loader.get_active_location()
	_assert(room != null and room.name == root_name, "wrong room root: " + root_name)
	if room == null:
		return
	var report: Dictionary = room.get("build_report")
	_assert(int(report.get("placements", 0)) == placement_count, "placement count: " + location_id)
	_assert(int(report.get("loaded", 0)) == placement_count, "model coverage: " + location_id)
	_assert(int(report.get("fallbacks", -1)) == 0, "fallback model: " + location_id)
	for actor_name in ["Agent", "JueAgent", "LocalCharacterSpawner"]:
		_assert(
			room.has_node(actor_name) == (actor_name in expected_cast),
			"cast policy mismatch: %s/%s" % [location_id, actor_name],
		)
	_assert(_visible_semantic_ids().has(required_object_id), "semantic object missing: " + required_object_id)
	var found_portals := 0
	for child in room.get_children():
		if str(child.name).begins_with("Portal_"):
			found_portals += 1
	_assert(found_portals == portal_count, "portal count %s: expected %d got %d" % [location_id, portal_count, found_portals])
	_check_navigation(room, location_id)


## [S3.2][S4.3] 验证阳台植物与落地灯复用通用有状态交互。
func _check_sunroom_state(room: Node3D) -> void:
	var semantic_world := root.get_node("SemanticWorld")
	var plant_body := room.get_node_or_null(
		"SunroomPlantMain/PhysicsBody"
	)
	var plant = semantic_world.get_object("sunroom_plant_main")
	_assert(plant_body != null and plant != null, "sunroom plant state missing")
	if plant_body != null and plant != null:
		var before := float(plant.properties.get("moisture", 0.0))
		var result: Dictionary = plant_body.perform_interaction("water", "main_agent")
		var after := float(
			semantic_world.get_object("sunroom_plant_main").properties.get("moisture", 0.0)
		)
		_assert(bool(result.get("success", false)) and after > before, "sunroom water failed")
	var lamp_body := room.get_node_or_null("SunroomLights/PhysicsBody")
	var lamp_light := room.get_node_or_null(
		"SunroomLights/GeneratedWarmLight"
	) as OmniLight3D
	_assert(lamp_body != null and lamp_light != null, "sunroom lamp state missing")
	if lamp_body != null and lamp_light != null:
		var result: Dictionary = lamp_body.perform_interaction("turn_off", "main_agent")
		_assert(bool(result.get("success", false)), "sunroom lamp turn_off failed")
		_assert(is_zero_approx(lamp_light.light_energy), "sunroom lamp stayed on")
	var planner := GOAPPlanner.new()
	room.add_child(planner)
	var water_plan := planner.plan("water_plant")
	var rest_plan := planner.plan("rest_on_sofa")
	_assert(
		water_plan.size() == 5
			and String(water_plan[0].params.get("target", "")) == "sunroom_watering_can"
			and String(water_plan[2].params.get("target", "")) == "sunroom_plant_main",
		"sunroom watering blueprint did not resolve",
	)
	_assert(
		rest_plan.size() == 3
			and String(rest_plan[0].params.get("target", "")) == "sunroom_armchair",
		"sunroom rest blueprint did not resolve",
	)
	planner.queue_free()


## [S2.2] 验证角色出生点到房间中心可由生成导航网格连通。
func _check_navigation(room: Node3D, location_id: String) -> void:
	var region := room.get_node_or_null(
		"GeneratedRoom/Structure/NavigationRegion3D"
	) as NavigationRegion3D
	var actor := room.get_node_or_null("Agent") as Node3D
	_assert(region != null and actor != null, "navigation inputs missing: " + location_id)
	if region == null or actor == null:
		return
	var map_rid := region.get_navigation_map()
	var path := NavigationServer3D.map_get_path(
		map_rid, actor.global_position, room.global_position, true
	)
	_assert(path.size() >= 2, "room center unreachable: " + location_id)


## [S2.2] 返回当前地点对 AI 可见的稳定语义 ID。
func _visible_semantic_ids() -> Array[String]:
	var result: Array[String] = []
	for item in root.get_node("SemanticWorld").list_objects():
		result.append(String(item.get("id", "")))
	return result


## [S2.2] 等待构建、角色出生恢复和 NavigationServer 同步。
func _settle() -> void:
	for _frame in range(4):
		await physics_frame
		await process_frame


## [S2.2] 累积失败以一次输出完整诊断。
func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("MULTI_ROOM_HOME_FAIL: " + message)
