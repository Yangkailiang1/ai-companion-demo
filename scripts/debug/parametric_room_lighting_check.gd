# Verifies: S1.2, S2.5, S4.1
# Covers: five authored profiles -> one active rig -> room switch -> old rig off

extends SceneTree

var failed := false


## [S1.2][S2.5] Loads the stitched home and verifies bounded active-room lights.
func _init() -> void:
	call_deferred("_run")


## [S1.2][S2.5][S4.1] Exercises authored values, runtime light count and switch.
func _run() -> void:
	OS.set_environment("AI_GAMES_WORLD_MODE", "parametric")
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	for _frame in range(4):
		await process_frame
	var world := scene.get_node("WorldRoot")
	var rooms := {
		"living_room": world.get_node("LivingRoom"),
		"kitchen": world.get_node("Kitchen"),
		"bedroom": world.get_node("Bedroom"),
		"study": world.get_node("Study"),
		"sunroom": world.get_node("Sunroom"),
	}
	_verify_profiles(rooms)
	_verify_active_rigs(rooms, "living_room")
	_assert(world.travel_to("kitchen"), "could not activate kitchen")
	await process_frame
	_verify_active_rigs(rooms, "kitchen")
	var environment := world.get_node("WorldEnvironment").environment as Environment
	_assert(environment.ssao_enabled, "SSAO contact shading is disabled")
	_assert(environment.ambient_light_energy <= 0.55, "ambient wash is too strong")
	print("PARAMETRIC_ROOM_LIGHTING_%s active=kitchen ssao=%s" % [
		"FAIL" if failed else "PASS", environment.ssao_enabled,
	])
	scene.free()
	quit(1 if failed else 0)


## [S1.2][S4.1] Ensures each room owns a distinct three-point authored rig.
func _verify_profiles(rooms: Dictionary) -> void:
	var colors: Array[Color] = []
	for location_id in rooms:
		var rig: Node = (rooms[location_id] as Node).get_node_or_null("RoomLighting")
		_assert(rig != null, "%s has no RoomLighting" % location_id)
		if rig == null:
			continue
		var key := rig.get_node_or_null("KeyLight") as DirectionalLight3D
		var fill := rig.get_node_or_null("WarmFillLight") as OmniLight3D
		var accent := rig.get_node_or_null("AccentLight") as OmniLight3D
		_assert(key != null and fill != null and accent != null,
			"%s does not own key/fill/accent" % location_id)
		if key != null:
			colors.append(key.light_color)
			_assert(key.shadow_enabled, "%s key light has no shadows" % location_id)
	_assert(_unique_colors(colors) >= 3, "room profiles are not visually distinct")


## [S1.2][S2.5] Confirms only the active semantic room contributes local lights.
func _verify_active_rigs(rooms: Dictionary, active_id: String) -> void:
	var total := 0
	for location_id in rooms:
		var rig: Node = (rooms[location_id] as Node).get_node("RoomLighting")
		var count: int = rig.get_active_light_count()
		total += count
		_assert(count == (3 if location_id == active_id else 0),
			"%s light count=%d while active=%s" % [location_id, count, active_id])
	_assert(total == 3, "stitched home should expose exactly three room lights")


## [S1.2] Counts distinct colors with a small floating point tolerance.
func _unique_colors(colors: Array[Color]) -> int:
	var unique: Array[Color] = []
	for color in colors:
		if unique.all(func(existing: Color) -> bool: return not existing.is_equal_approx(color)):
			unique.append(color)
	return unique.size()


## [T4.2] Records a stable acceptance failure.
func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	failed = true
	push_error("PARAMETRIC_ROOM_LIGHTING_FAIL: " + message)
