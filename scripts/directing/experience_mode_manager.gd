# Roadmap: D2, D3, C9
# Responsibility: 显式管理自由生活与剧情演出两种互斥体验模式。
# Collaborators: MessageBus, AutonomousBehaviorSystem, StoryDirector, StoryPlannerService
# Tests: scripts/debug/experience_modes_check.gd

extends Node

enum Mode { FREE, PERFORMANCE }

var _mode: Mode = Mode.FREE


## [D2][D3][C9] 连接模式请求，并以自由生活模式启动。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	MessageBus.experience_mode_requested.connect(_on_mode_requested)
	call_deferred("_apply_mode")


## [D3][C9] 返回稳定的英文模式 ID，供 UI、存档和测试使用。
func get_mode_name() -> String:
	return "performance" if _mode == Mode.PERFORMANCE else "free"


## [D3][C9] 查询当前是否处于演出模式。
func is_performance_mode() -> bool:
	return _mode == Mode.PERFORMANCE


## [D3] 进入演出模式；自主生活暂停，但不会自动生成或播放剧本。
func enter_performance_mode() -> void:
	if _mode == Mode.PERFORMANCE:
		return
	_mode = Mode.PERFORMANCE
	_apply_mode()


## [C9][D3] 返回自由模式，取消未完成的规划/演出并恢复自主生活。
func enter_free_mode() -> void:
	if has_node("/root/StoryPlannerService"):
		get_node("/root/StoryPlannerService").cancel_request("return_to_free_mode")
	if has_node("/root/StoryDirector"):
		get_node("/root/StoryDirector").cancel_story("return_to_free_mode")
	_mode = Mode.FREE
	_apply_mode()


## [D3][C9] 将总线中的字符串请求转换为受限模式切换。
func _on_mode_requested(mode_name: String) -> void:
	if mode_name == "performance":
		enter_performance_mode()
	elif mode_name == "free":
		enter_free_mode()


## [D2][D3][C9] 应用调度开关并广播模式变化。
func _apply_mode() -> void:
	var performance := _mode == Mode.PERFORMANCE
	if has_node("/root/AutonomousBehaviorSystem"):
		get_node("/root/AutonomousBehaviorSystem").set_scheduler_enabled(not performance)
	MessageBus.experience_mode_changed.emit(get_mode_name())
	MessageBus.ui_status_changed.emit(
		"演出模式：请输入剧本，由 AI 编排角色" if performance
		else "自由模式：角色会自主生活，也可以正常对话",
		"performance" if performance else "free",
	)
