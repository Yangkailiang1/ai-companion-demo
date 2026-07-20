class_name RoomNavigation

extends RefCounted

const CONFIG_PATH := "res://data/scene_config.json"
const DEFAULT_MIN := Vector3(-3.25, 0.0, -3.15)
const DEFAULT_MAX := Vector3(3.25, 0.0, 3.15)

var bounds_min := DEFAULT_MIN
var bounds_max := DEFAULT_MAX
var waypoints: Dictionary = {}
var routes: Dictionary = {}
var wander_names: Array[String] = []
var obstacles: Array[Dictionary] = []


func _init() -> void:
	_load_config()


func has_waypoint(name: String) -> bool:
	return waypoints.has(name)


func get_waypoint(name: String) -> Vector3:
	return waypoints.get(name, Vector3.ZERO)


func get_route(name: String = "room_perimeter", laps: int = 1) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var route_names: Array = routes.get(name, [])
	for _lap in range(clampi(laps, 1, 3)):
		for waypoint_name in route_names:
			if has_waypoint(String(waypoint_name)):
				result.append(get_waypoint(String(waypoint_name)))
		if not route_names.is_empty() and has_waypoint(String(route_names[0])):
			result.append(get_waypoint(String(route_names[0])))
	return result


func get_wander_point(index: int = -1) -> Vector3:
	if wander_names.is_empty():
		return Vector3.ZERO
	var resolved_index := index
	if resolved_index < 0:
		resolved_index = randi() % wander_names.size()
	resolved_index = posmod(resolved_index, wander_names.size())
	return get_waypoint(wander_names[resolved_index])


func get_wander_point_away(from_position: Vector3, minimum_distance: float = 1.0, index: int = -1) -> Vector3:
	if wander_names.is_empty():
		return Vector3.ZERO
	var start_index := index if index >= 0 else randi() % wander_names.size()
	for offset in range(wander_names.size()):
		var candidate := get_wander_point(start_index + offset)
		if candidate.distance_to(from_position) >= minimum_distance:
			return candidate
	return get_wander_point(start_index)


func is_safe_position(position: Vector3) -> bool:
	return position.x >= bounds_min.x and position.x <= bounds_max.x \
		and position.z >= bounds_min.z and position.z <= bounds_max.z


func clamp_to_bounds(position: Vector3) -> Vector3:
	return Vector3(
		clampf(position.x, bounds_min.x, bounds_max.x),
		0.0,
		clampf(position.z, bounds_min.z, bounds_max.z)
	)


func is_walkable_position(position: Vector3) -> bool:
	if not is_safe_position(position):
		return false
	for obstacle in obstacles:
		var obstacle_min: Vector3 = obstacle["min"]
		var obstacle_max: Vector3 = obstacle["max"]
		if position.x >= obstacle_min.x and position.x <= obstacle_max.x \
			and position.z >= obstacle_min.z and position.z <= obstacle_max.z:
			return false
	return true


func _load_config() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		_install_defaults()
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not parsed.has("navigation"):
		_install_defaults()
		return
	var config: Dictionary = parsed["navigation"]
	var bounds: Dictionary = config.get("bounds", {})
	bounds_min = _to_vec3(bounds.get("min", [DEFAULT_MIN.x, 0.0, DEFAULT_MIN.z]))
	bounds_max = _to_vec3(bounds.get("max", [DEFAULT_MAX.x, 0.0, DEFAULT_MAX.z]))
	for waypoint_name in config.get("waypoints", {}):
		var point := _to_vec3(config["waypoints"][waypoint_name])
		if is_safe_position(point):
			waypoints[String(waypoint_name)] = point
	for route_name in config.get("routes", {}):
		routes[String(route_name)] = config["routes"][route_name]
	for raw_obstacle in config.get("obstacles", []):
		if raw_obstacle is Dictionary:
			obstacles.append({
				"name": String(raw_obstacle.get("name", "obstacle")),
				"min": _to_vec3(raw_obstacle.get("min", Vector3.ZERO)),
				"max": _to_vec3(raw_obstacle.get("max", Vector3.ZERO)),
			})
	for waypoint_name in config.get("wander_points", []):
		if has_waypoint(String(waypoint_name)):
			wander_names.append(String(waypoint_name))
	if waypoints.is_empty():
		_install_defaults()


func _install_defaults() -> void:
	bounds_min = DEFAULT_MIN
	bounds_max = DEFAULT_MAX
	waypoints = {
		"room_center": Vector3(-0.2, 0.0, -0.6),
		"perimeter_n": Vector3(0.2, 0.0, -2.7),
		"perimeter_e": Vector3(3.0, 0.0, 1.0),
		"perimeter_s": Vector3(0.4, 0.0, 3.0),
		"perimeter_w": Vector3(-3.1, 0.0, 0.0),
	}
	routes = {"room_perimeter": ["perimeter_n", "perimeter_e", "perimeter_s", "perimeter_w"]}
	wander_names.assign(["room_center", "perimeter_n", "perimeter_e", "perimeter_s", "perimeter_w"])
	obstacles = []


func _to_vec3(value: Variant) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	if value is Dictionary:
		return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))
	return Vector3.ZERO
