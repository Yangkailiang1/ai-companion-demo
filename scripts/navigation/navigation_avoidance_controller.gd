# Roadmap: C4.1
# Responsibility: 配置 NavigationAgent3D 互惠避障、运动优先级和静止让路速度；
#   不选择路径、不管理动作队列，也不决定角色目标。
# Collaborators: NavigationAgent3D, RoomNavigation, AgentBase
# Tests: scripts/debug/navigation_avoidance_check.gd

class_name NavigationAvoidanceController
extends RefCounted

const AGENT_RADIUS_METERS: float = 0.36
const NEIGHBOR_DISTANCE_METERS: float = 1.8
const MAX_NEIGHBORS: int = 6
const TIME_HORIZON_AGENTS: float = 1.5
const TIME_HORIZON_OBSTACLES: float = 0.5
const MAX_SPEED_METERS: float = 3.0
const SOCIAL_CLEARANCE_METERS: float = 0.6
const IDLE_PRIORITY: float = 0.1
const IDLE_YIELD_MAX_SPEED_METERS: float = 0.65


## [C4.1] 配置 RVO 参数和回调所需的基础状态。
func configure(navigation_agent: NavigationAgent3D) -> void:
	navigation_agent.avoidance_enabled = true
	navigation_agent.radius = AGENT_RADIUS_METERS
	navigation_agent.neighbor_distance = NEIGHBOR_DISTANCE_METERS
	navigation_agent.max_neighbors = MAX_NEIGHBORS
	navigation_agent.time_horizon_agents = TIME_HORIZON_AGENTS
	navigation_agent.time_horizon_obstacles = TIME_HORIZON_OBSTACLES
	navigation_agent.max_speed = MAX_SPEED_METERS
	navigation_agent.avoidance_priority = IDLE_PRIORITY


## [C4.1] 移动角色使用确定性的较高优先级，打破正面对称僵局。
func begin_movement(agent_id: String, navigation_agent: NavigationAgent3D) -> void:
	navigation_agent.avoidance_priority = 0.5 + _stable_hash01(agent_id) * 0.4


## [C4.1] 移动结束时清除期望速度，并恢复可让路的静止优先级。
func finish_movement(navigation_agent: NavigationAgent3D) -> void:
	navigation_agent.velocity = Vector3.ZERO
	navigation_agent.avoidance_priority = IDLE_PRIORITY


## [C4.1] 静止角色仅在候选位置可行走时执行小幅互惠让路。
## 返回 true 表示本帧发生了物理位移。
func apply_idle_yield(
	body: CharacterBody3D,
	safe_velocity: Vector3,
	delta_seconds: float,
) -> bool:
	var yield_velocity := safe_velocity.limit_length(IDLE_YIELD_MAX_SPEED_METERS)
	if yield_velocity.length() <= 0.05:
		return false
	var candidate := body.global_position + yield_velocity * delta_seconds
	if not RoomNavigation.new().is_walkable_position(candidate):
		return false
	body.velocity = yield_velocity
	body.move_and_slide()
	body.velocity = Vector3.ZERO
	return true


## [C4.1] 将稳定角色 ID 映射到 0-1，用于可复现的 RVO 优先级。
func _stable_hash01(agent_id: String) -> float:
	var hash_value := 0
	for index in range(agent_id.length()):
		hash_value = (hash_value * 31 + agent_id.unicode_at(index)) & 0x7FFFFFFF
	return float(hash_value % 1000) / 1000.0
