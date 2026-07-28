# Roadmap: C4.5, C9.3
# Responsibility: 管理单个角色的 ActionExecutor 生命周期并转发成功/失败；
#   不执行具体 primitive、不决定活动，也不修改物体状态。
# Collaborators: AgentBase, ActionExecutor
# Tests: scripts/debug/action_failure_contract_check.gd

class_name AgentActionRuntime
extends Node

var _agent: Node3D
var _active_executor: ActionExecutor

signal queue_completed
signal queue_failed(reason: String, context: Dictionary)


## [C4.5][C9.3] 绑定拥有此运行时的角色；纯生命周期配置。
func configure(agent: Node3D) -> void:
	_agent = agent


## [C4.5][C9.3] 取消旧队列并启动最新动作；latest decision wins。
func start(actions: Array) -> void:
	cancel("superseded")
	if not is_instance_valid(_agent):
		queue_failed.emit("agent_missing", {})
		return
	var executor := ActionExecutor.new()
	_active_executor = executor
	add_child(executor)
	executor.queue_completed.connect(_on_executor_completed.bind(executor))
	executor.queue_failed.connect(_on_executor_failed.bind(executor))
	executor.start_queue(_agent, actions)


## [C4.5] 取消当前执行器和移动；取消本身不伪造成功或失败完成事件。
func cancel(reason: String = "cancelled") -> void:
	if is_instance_valid(_active_executor):
		_active_executor.cancel()
		_active_executor.queue_free()
		_active_executor = null
	if is_instance_valid(_agent) and _agent.has_method("cancel_movement"):
		_agent.cancel_movement(reason)


## [C4.5] 成功队列回调：清理执行器并向 AgentBase 转发一次。
func _on_executor_completed(_agent_id: String, executor: ActionExecutor) -> void:
	if executor != _active_executor:
		return
	_active_executor = null
	queue_completed.emit()
	executor.queue_free()


## [C4.5] 失败队列回调：清理执行器并转发稳定原因和上下文。
func _on_executor_failed(
	_agent_id: String,
	reason: String,
	context: Dictionary,
	executor: ActionExecutor,
) -> void:
	if executor != _active_executor:
		return
	_active_executor = null
	queue_failed.emit(reason, context)
	executor.queue_free()
