# agent_base.gd — Agent 基础控制器
# 附在 Godot 角色节点上，负责：
# 1. 接收 ActionExecutor 的 Primitive 指令
# 2. 执行导航（NavAgent3D，含无 NavMesh 时 fallback）
# 3. 响应 Simulation 触发
# 4. 根据移动状态发出 idle/walk 表现层 cue（CharacterAnimationDriver 监听）

extends CharacterBody3D

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

# 无 NavMesh 时的直接移动 fallback
var _navmesh_ready: bool = false
var _navmesh_checked: bool = false
const MOVE_SPEED: float = 3.0
const ARRIVE_THRESHOLD: float = 0.5
const MOVEMENT_TIMEOUT: float = 20.0
const STUCK_TIMEOUT: float = 2.5
const STUCK_DISTANCE_EPSILON: float = 0.025
var _movement_elapsed: float = 0.0
var _stuck_elapsed: float = 0.0
var _last_progress_position := Vector3.ZERO
var _active_executor: ActionExecutor = null
var _locomotion_sequence_depth: int = 0

signal arrived
signal movement_finished(success: bool, reason: String)


func _ready():
	add_to_group("agents")
	# 连接信号
	MessageBus.emit_actions.connect(_on_emit_actions)

	# Idle Timer — 自主唤醒
	if not idle_timer:
		idle_timer = Timer.new()
		add_child(idle_timer)
	idle_timer.wait_time = 90.0 + randf() * 60.0  # 90-150 秒随机间隔，避免自主发言打断玩家
	idle_timer.timeout.connect(_on_idle_timer)
	idle_timer.start()

	# 确保有 NavigationAgent
	if not navigation_agent:
		navigation_agent = NavigationAgent3D.new()
		add_child(navigation_agent)

	# 查找 CharacterAnimationDriver（如果场景中存在）
	animation_driver = _find_animation_driver()

	# 延迟检查 NavMesh 是否可用
	await get_tree().process_frame
	_check_navmesh()


func _check_navmesh() -> void:
	_navmesh_checked = true
	# A world can expose a map RID even when it contains no NavigationRegion.
	# Only opt into NavigationAgent routing when at least one region was baked.
	var navigation_map := navigation_agent.get_navigation_map()
	_navmesh_ready = navigation_map != RID() \
		and NavigationServer3D.map_get_regions(navigation_map).size() > 0 \
		and NavigationServer3D.map_get_iteration_id(navigation_map) >= 2


func _on_emit_actions(agent_id: String, actions: Array):
	if agent_id != agent_name: return

	# Latest decision wins. CognitiveCycle already preserves player messages in FIFO;
	# once a new decision is emitted, the previous physical queue must not fight it.
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


func move_to_position(target: Vector3) -> void:
	var navigation := RoomNavigation.new()
	target_position = navigation.clamp_to_bounds(target)
	if not _navmesh_ready:
		_check_navmesh()
	has_target = true
	is_moving = true
	_movement_elapsed = 0.0
	_stuck_elapsed = 0.0
	_last_progress_position = global_position
	MessageBus.performance_cue.emit("walk", {"source": "agent"})

	# 尝试使用 NavAgent，失败时 fallback 到直接移动
	if _navmesh_ready:
		navigation_agent.target_position = target_position
	else:
		# 重新检查一次
		if not _navmesh_checked:
			_check_navmesh()


func look_at_target(target_id: String) -> void:
	var obj = SemanticWorld.get_object(target_id)
	if obj:
		look_at(Vector3(obj.position.x, global_position.y, obj.position.z), Vector3.UP)


func _physics_process(delta: float) -> void:
	if not is_moving or not has_target:
		return
	_movement_elapsed += delta
	if _movement_elapsed >= MOVEMENT_TIMEOUT:
		_finish_movement(false, "timeout")
		return

	if _navmesh_ready:
		# NavMesh 模式
		if navigation_agent.is_navigation_finished():
			_finish_movement(true, "arrived")
			return
		var next_pos = navigation_agent.get_next_path_position()
		var direction = (next_pos - global_position).normalized()
		velocity = direction * MOVE_SPEED
	else:
		# 直接移动 fallback（无 NavMesh）
		var to_target = target_position - global_position
		if to_target.length() < ARRIVE_THRESHOLD:
			velocity = Vector3.ZERO
			_finish_movement(true, "arrived")
			return
		var direction = to_target.normalized()
		velocity = direction * MOVE_SPEED

	move_and_slide()
	if global_position.distance_to(_last_progress_position) >= STUCK_DISTANCE_EPSILON:
		_last_progress_position = global_position
		_stuck_elapsed = 0.0
	else:
		_stuck_elapsed += delta
		if _stuck_elapsed >= STUCK_TIMEOUT:
			_finish_movement(false, "stuck")
			return

	# 面向移动方向
	if velocity.length() > 0.1:
		var look_dir = Vector3(velocity.x, 0, velocity.z).normalized()
		if look_dir.length() > 0.1:
			# The imported penguin's visual forward axis is local +Z (not Godot's
			# conventional -Z), so align +Z with the current velocity direction.
			var target_yaw := atan2(look_dir.x, look_dir.z)
			rotation.y = lerp_angle(rotation.y, target_yaw, minf(delta * 9.0, 1.0))


func _finish_movement(success: bool = true, reason: String = "arrived") -> void:
	is_moving = false
	has_target = false
	velocity = Vector3.ZERO
	if _locomotion_sequence_depth == 0 or not success:
		MessageBus.performance_cue.emit("idle", {"source": "agent"})
	if success:
		arrived.emit()
	movement_finished.emit(success, reason)


func cancel_movement(reason: String = "cancelled") -> void:
	_locomotion_sequence_depth = 0
	if not is_moving and not has_target:
		return
	_finish_movement(false, reason)


func begin_locomotion_sequence() -> void:
	_locomotion_sequence_depth += 1


func end_locomotion_sequence() -> void:
	_locomotion_sequence_depth = maxi(_locomotion_sequence_depth - 1, 0)
	if _locomotion_sequence_depth == 0 and not is_moving:
		MessageBus.performance_cue.emit("idle", {"source": "agent", "sequence_complete": true})


func _on_idle_timer() -> void:
	MessageBus.route_idle_wake(agent_name)


func _on_actions_finished() -> void:
	current_activity = "idle"
	idle_timer.start()


func _find_animation_driver() -> Node:
	for child in get_children():
		if child.get_script() and child.get_script().resource_path.ends_with("character_animation_driver.gd"):
			return child
	return null
