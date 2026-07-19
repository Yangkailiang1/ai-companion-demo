# agent_base.gd — Agent 基础控制器
# 附在 Godot 角色节点上，负责：
# 1. 接收 ActionExecutor 的 Primitive 指令
# 2. 执行导航（NavAgent3D）、播放动画
# 3. 响应 Simulation 触发

extends CharacterBody3D

@export var agent_name: String = "main_agent"

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var idle_timer: Timer = $IdleTimer

# 当前状态
var current_activity: String = "idle"
var current_emotion: String = "neutral"
var is_moving: bool = false

# 目标位置
var target_position: Vector3
var has_target: bool = false

signal arrived


func _ready():
	# 连接信号
	SignalBus.emit_actions.connect(_on_emit_actions)

	# Idle Timer — 自主唤醒
	if not idle_timer:
		idle_timer = Timer.new()
		add_child(idle_timer)
	idle_timer.wait_time = 30.0 + randf() * 30.0  # 30-60 秒随机间隔
	idle_timer.timeout.connect(_on_idle_timer)
	idle_timer.start()

	# 确保有 NavigationAgent
	if not navigation_agent:
		navigation_agent = NavigationAgent3D.new()
		add_child(navigation_agent)


func _on_emit_actions(agent_id: String, actions: Array):
	if agent_id != agent_name: return

	var executor = ActionExecutor.new()
	add_child(executor)
	executor.queue_completed.connect(func(_id):
		_on_actions_finished()
		idle_timer.start()
	)
	executor.start_queue(self, actions)


func move_to(target: Vector3) -> void:
	target_position = target
	has_target = true
	navigation_agent.target_position = target
	is_moving = true


func look_at_target(target_id: String) -> void:
	# 转向目标物体
	var obj = SemanticWorld.get_object(target_id)
	if obj:
		look_at(obj.position, Vector3.UP)


func _physics_process(delta: float) -> void:
	if not is_moving or not has_target:
		return

	if navigation_agent.is_navigation_finished():
		is_moving = false
		has_target = false
		arrived.emit()
		return

	var next_pos = navigation_agent.get_next_path_position()
	var direction = (next_pos - global_position).normalized()
	velocity = direction * 3.0  # 移动速度
	move_and_slide()

	# 面向移动方向
	if direction.length() > 0.1:
		look_at(global_position + direction, Vector3.UP)


func _on_idle_timer() -> void:
	# 自主行为触发：通过 Message Bus 通知 CognitiveCycle
	MessageBus.route_idle_wake(agent_name)


func _on_actions_finished() -> void:
	current_activity = "idle"
	idle_timer.start()
