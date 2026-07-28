# agent_base.gd — Agent 基础控制器
# Roadmap: C4.1, C9.3, T2.2
# Responsibility: 执行导航（NavMesh 路径追踪 + avoidance 避障 + 无 NavMesh fallback）、
#   角色生命周期和表现层 cue；不执行 AI 决策、动作规划或物体交互逻辑。
# Collaborators: MessageBus, NavigationServer3D, CharacterAnimationDriver, ActionExecutor
# Tests: scripts/debug/spatial_autonomy_check.gd, scripts/debug/navigation_avoidance_check.gd

extends CharacterBody3D

const NavigationRecoveryClass = preload("res://scripts/navigation/navigation_recovery.gd")
const NavigationAvoidanceClass = preload(
	"res://scripts/navigation/navigation_avoidance_controller.gd"
)
const SOCIAL_CLEARANCE_METERS: float = NavigationAvoidanceClass.SOCIAL_CLEARANCE_METERS

@export var agent_name: String = "main_agent"

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var idle_timer: Timer = $IdleTimer

# v0.2: CharacterAnimationDriver 引用（可选，场景中可配置）
var animation_driver: Node = null

# 当前状态
var current_activity: String = "idle"
var current_emotion: String = "neutral"
var is_moving: bool = false

# 目标位置
var target_position: Vector3
var has_target: bool = false

# --- Movement parameters ---
const MOVE_SPEED: float = 3.0
const ARRIVE_THRESHOLD: float = 0.5
const MOVEMENT_TIMEOUT: float = 20.0
const STUCK_TIMEOUT: float = 2.5
const STUCK_DISTANCE_EPSILON: float = 0.025

# --- Internal state ---
var _navmesh_ready: bool = false
var _navmesh_checked: bool = false
var _movement_elapsed: float = 0.0
var _stuck_elapsed: float = 0.0
var _last_progress_position := Vector3.ZERO
var _active_executor: ActionExecutor = null
var _locomotion_sequence_depth: int = 0
var _facing_tween: Tween
var _avoidance_enabled: bool = false
var _navigation_recovery = NavigationRecoveryClass.new()
var _avoidance_controller = NavigationAvoidanceClass.new()

signal arrived
signal movement_finished(success: bool, reason: String)


## [C4.1][T2.2] Initializes groups, signals, avoidance and late NavMesh check.
func _ready() -> void:
	add_to_group("agents")
	MessageBus.emit_actions.connect(_on_emit_actions)

	if not idle_timer:
		idle_timer = Timer.new()
		add_child(idle_timer)
	idle_timer.wait_time = 90.0 + randf() * 60.0
	idle_timer.timeout.connect(_on_idle_timer)
	idle_timer.start()

	if not navigation_agent:
		navigation_agent = NavigationAgent3D.new()
		add_child(navigation_agent)

	animation_driver = _find_animation_driver()

	await get_tree().process_frame
	_check_navmesh()
	_configure_avoidance()


## [C4.1] Configures NavigationAgent3D avoidance using named meter/second values.
## Assigns deterministic avoidance priority based on agent_name hash so two head-on
## actors never remain stuck forever. Higher hash = higher priority.
func _configure_avoidance() -> void:
	_avoidance_controller.configure(navigation_agent)
	if not navigation_agent.velocity_computed.is_connected(_on_velocity_computed):
		navigation_agent.velocity_computed.connect(_on_velocity_computed)
	_avoidance_enabled = true


## [T2.2] Validates NavMesh readiness: map exists, has regions and is baked.
func _check_navmesh() -> void:
	_navmesh_checked = true
	var navigation_map := navigation_agent.get_navigation_map()
	_navmesh_ready = navigation_map != RID() \
		and NavigationServer3D.map_get_regions(navigation_map).size() > 0 \
		and NavigationServer3D.map_get_iteration_id(navigation_map) >= 2


## [C9.3] Receives action primitives from runtime; latest decision wins.
## Side effects: cancels previous executor and movement, starts new queue.
func _on_emit_actions(agent_id: String, actions: Array) -> void:
	if agent_id != agent_name: return

	if is_instance_valid(_active_executor):
		_active_executor.cancel()
		_active_executor.queue_free()
		_active_executor = null
	cancel_movement("superseded")

	current_activity = "executing_actions"
	var executor = ActionExecutor.new()
	_active_executor = executor
	add_child(executor)
	executor.queue_completed.connect(func(_id):
		if _active_executor == executor:
			_active_executor = null
			_on_actions_finished()
		if is_instance_valid(executor):
			executor.queue_free()
	)
	executor.start_queue(self, actions)


func move_to(target: Vector3) -> void:
	move_to_position(target)


## [C4.1][T2.2] Commits target position, emits walk cue, engages NavMesh pathfinder
## or fallback. Side effects: resets movement timers, starts physical locomotion.
func move_to_position(target: Vector3) -> void:
	var navigation := RoomNavigation.new()
	target_position = navigation.clamp_to_bounds(target)
	if not _navmesh_ready:
		_check_navmesh()
	if _navmesh_ready and not _avoidance_enabled:
		_configure_avoidance()
	has_target = true
	is_moving = true
	_movement_elapsed = 0.0
	_stuck_elapsed = 0.0
	_last_progress_position = global_position
	_navigation_recovery.reset(target_position)
	_avoidance_controller.begin_movement(agent_name, navigation_agent)
	MessageBus.performance_cue.emit("walk", {"source": "agent", "agent_id": agent_name})

	if _navmesh_ready:
		navigation_agent.target_position = target_position
	else:
		if not _navmesh_checked:
			_check_navmesh()


func look_at_target(target_id: String) -> void:
	var obj = SemanticWorld.get_object(target_id)
	if obj:
		turn_towards_world_position(obj.position, 0.3)


func turn_towards_world_position(world_position: Vector3, duration: float = 0.3) -> void:
	var flat_direction := Vector3(
		world_position.x - global_position.x,
		0.0,
		world_position.z - global_position.z
	)
	if flat_direction.length_squared() < 0.0001:
		return
	var target_yaw := atan2(flat_direction.x, flat_direction.z)
	if _facing_tween and _facing_tween.is_valid():
		_facing_tween.kill()
	_facing_tween = create_tween()
	_facing_tween.tween_property(self, "rotation:y", target_yaw, maxf(duration, 0.01))


## [C4.1] Physics tick: submits desired velocity to NavigationAgent for avoidance
## when NavMesh is ready, or uses deterministic direct fallback without NavMesh.
## Does NOT call move_and_slide() in NavMesh mode — that happens in the
## velocity_computed callback so NavigationServer can compute safe velocity first.
func _physics_process(delta: float) -> void:
	if not is_moving or not has_target:
		return
	_movement_elapsed += delta
	if _movement_elapsed >= MOVEMENT_TIMEOUT:
		_finish_movement(false, "timeout")
		return

	if _navmesh_ready:
		if navigation_agent.is_navigation_finished():
			if _navigation_recovery.resume_goal_after_detour(navigation_agent):
				_stuck_elapsed = 0.0
				_last_progress_position = global_position
				return
			var reached_target := global_position.distance_to(target_position) <= ARRIVE_THRESHOLD
			_finish_movement(reached_target, "arrived" if reached_target else "unreachable")
			return
		var next_pos: Vector3 = navigation_agent.get_next_path_position()
		var desired_velocity: Vector3 = (next_pos - global_position).normalized() * MOVE_SPEED
		navigation_agent.velocity = desired_velocity
	else:
		var to_target := target_position - global_position
		if to_target.length() < ARRIVE_THRESHOLD:
			velocity = Vector3.ZERO
			_finish_movement(true, "arrived")
			return
		velocity = to_target.normalized() * MOVE_SPEED
		move_and_slide()
		_update_post_movement(delta)


## [C4.1] Callback from NavigationServer3D with the safe avoidance velocity.
## Applies the computed velocity to the CharacterBody3D and performs post-movement
## steps. Only fires during NavMesh-active movement.
func _on_velocity_computed(safe_velocity: Vector3) -> void:
	if not is_moving:
		_avoidance_controller.apply_idle_yield(
			self, safe_velocity, get_physics_process_delta_time()
		)
		return
	velocity = safe_velocity
	move_and_slide()
	_update_post_movement(get_physics_process_delta_time())


## [C4.1] Shared post-movement steps: stuck detection and facing direction update.
func _update_post_movement(delta: float) -> void:
	if global_position.distance_to(_last_progress_position) >= STUCK_DISTANCE_EPSILON:
		_last_progress_position = global_position
		_stuck_elapsed = 0.0
	else:
		_stuck_elapsed += delta
		if _stuck_elapsed >= STUCK_TIMEOUT:
			var recovery: Dictionary = _navigation_recovery.try_replan(navigation_agent, global_position)
			if bool(recovery.get("success", false)):
				print("AgentBase[%s]: replanning via %s" % [agent_name, recovery.get("detour")])
				_stuck_elapsed = 0.0
				_last_progress_position = global_position
				return
			_finish_movement(false, "stuck")
			return

	if velocity.length() > 0.1:
		var look_dir := Vector3(velocity.x, 0, velocity.z).normalized()
		if look_dir.length() > 0.1:
			var target_yaw := atan2(look_dir.x, look_dir.z)
			rotation.y = lerp_angle(rotation.y, target_yaw, minf(delta * 9.0, 1.0))


func _finish_movement(success: bool = true, reason: String = "arrived") -> void:
	is_moving = false
	has_target = false
	if not success and not reason.contains("cancel") and reason not in ["superseded", "test_complete"]:
		push_warning("AgentBase[%s]: movement failed (%s), position=%s target=%s velocity=%s"
			% [agent_name, reason, global_position, target_position, velocity])
	velocity = Vector3.ZERO
	_avoidance_controller.finish_movement(navigation_agent)
	if _locomotion_sequence_depth == 0 or not success:
		MessageBus.performance_cue.emit("idle", {"source": "agent", "agent_id": agent_name})
	if success:
		arrived.emit()
	movement_finished.emit(success, reason)


## [C4.1] Cancels current movement; submits zero velocity to NavigationAgent so
## deferred velocity_computed callbacks are harmless, then finishes with zero state.
func cancel_movement(reason: String = "cancelled") -> void:
	_locomotion_sequence_depth = 0
	_navigation_recovery.reset(target_position)
	if not is_moving and not has_target:
		return
	if _navmesh_ready:
		navigation_agent.velocity = Vector3.ZERO
	_finish_movement(false, reason)


func begin_locomotion_sequence() -> void:
	_locomotion_sequence_depth += 1


func end_locomotion_sequence() -> void:
	_locomotion_sequence_depth = maxi(_locomotion_sequence_depth - 1, 0)
	if _locomotion_sequence_depth == 0 and not is_moving:
		MessageBus.performance_cue.emit("idle", {"source": "agent", "agent_id": agent_name, "sequence_complete": true})


func _on_idle_timer() -> void:
	MessageBus.route_idle_wake(agent_name)


func _on_actions_finished() -> void:
	current_activity = "idle"
	idle_timer.start()
	MessageBus.action_queue_completed.emit(agent_name)


func _find_animation_driver() -> Node:
	for child in get_children():
		if child.get_script() and child.get_script().resource_path.ends_with("character_animation_driver.gd"):
			return child
	return null
