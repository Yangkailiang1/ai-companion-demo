# Roadmap: C4.1, C4.5
# Responsibility: 为被动态角色堵住的导航选择有限次安全绕行点；不移动角色、
#   不修改物体状态，也不决定高层行为。
# Collaborators: RoomNavigation, NavigationAgent3D
# Tests: scripts/debug/navigation_avoidance_check.gd, scripts/debug/autonomous_life_check.gd

class_name NavigationRecovery
extends RefCounted

const MAX_REPLAN_ATTEMPTS: int = 3
const MINIMUM_DETOUR_DISTANCE_METERS: float = 0.9

var _goal := Vector3.ZERO
var _attempts: int = 0
var _is_detouring: bool = false
var _used_points: Array[Vector3] = []


## [C4.1][C4.5] 为新的移动请求重置有限次恢复状态。
func reset(goal: Vector3) -> void:
	_goal = goal
	_attempts = 0
	_is_detouring = false
	_used_points.clear()


## [C4.1] 临时绕行点到达后恢复原始目标；返回是否消费了本次到达事件。
func resume_goal_after_detour(navigation_agent: NavigationAgent3D) -> bool:
	if not _is_detouring:
		return false
	_is_detouring = false
	navigation_agent.target_position = _goal
	return true


## [C4.1][C4.5] 选择尚未使用且偏离受阻直线的安全 waypoint。
## 成功时只更新 NavigationAgent 目标；失败时不修改现有目标。
func try_replan(navigation_agent: NavigationAgent3D, current: Vector3) -> Dictionary:
	if _attempts >= MAX_REPLAN_ATTEMPTS:
		return {"success": false, "reason": "replan_exhausted"}
	var candidates := _rank_candidates(current, navigation_agent)
	if candidates.is_empty():
		return {"success": false, "reason": "no_detour"}
	var detour: Vector3 = candidates[0]
	_used_points.append(detour)
	_attempts += 1
	_is_detouring = true
	navigation_agent.target_position = detour
	return {"success": true, "detour": detour, "attempt": _attempts}


## [C4.1] 对候选点按横向绕行收益排序，避免再次沿同一堵塞直线尝试。
func _rank_candidates(current: Vector3, navigation_agent: NavigationAgent3D) -> Array[Vector3]:
	var room := RoomNavigation.new()
	var candidates: Array[Vector3] = []
	for value in room.waypoints.values():
		var point: Vector3 = value
		if not room.is_walkable_position(point):
			continue
		if point.distance_to(current) < MINIMUM_DETOUR_DISTANCE_METERS:
			continue
		if _contains_used_point(point):
			continue
		candidates.append(point)
	candidates.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return _detour_score(a, current, navigation_agent) \
			< _detour_score(b, current, navigation_agent)
	)
	return candidates


## [C4.1] 较低分优先：兼顾目标距离，并奖励偏离当前到目标的受阻直线。
func _detour_score(
	point: Vector3,
	current: Vector3,
	navigation_agent: NavigationAgent3D,
) -> float:
	var direct := _goal - current
	var lateral_distance := 0.0
	if direct.length_squared() > 0.001:
		var progress := clampf((point - current).dot(direct) / direct.length_squared(), 0.0, 1.0)
		var projection := current + direct * progress
		lateral_distance = point.distance_to(projection)
	var actor_clearance := _minimum_actor_distance(point, navigation_agent)
	var occupied_penalty := 100.0 if actor_clearance < 1.0 else 0.0
	return point.distance_to(_goal) + point.distance_to(current) * 0.15 \
		- lateral_distance * 1.8 - minf(actor_clearance, 4.0) * 0.8 + occupied_penalty


## [C4.1] 返回候选点与其他角色的最近距离，避免把绕行点放在角色脚下。
func _minimum_actor_distance(point: Vector3, navigation_agent: NavigationAgent3D) -> float:
	var minimum_distance := INF
	var owner := navigation_agent.get_parent()
	for actor in navigation_agent.get_tree().get_nodes_in_group("agents"):
		if actor == owner or not actor is Node3D:
			continue
		minimum_distance = minf(minimum_distance, point.distance_to(actor.global_position))
	return minimum_distance


## [C4.1] 使用近似比较，避免浮点 waypoint 被重复选择。
func _contains_used_point(point: Vector3) -> bool:
	for used_point in _used_points:
		if used_point.distance_to(point) < 0.05:
			return true
	return false
