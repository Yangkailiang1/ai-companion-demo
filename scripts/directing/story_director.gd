# Roadmap: D1, D2
# Responsibility: 执行已验证的剧本 Beat，管理锁、超时、取消、恢复和演出事件；
# 不负责验证（交给 StorySchemaValidator），不执行具体动画。
# Collaborators: MessageBus, AutonomousBehaviorSystem, MemorySystem, StorySchemaValidator, CharacterAdapterRegistry
# Tests: scripts/debug/story_director_check.gd

extends Node

enum Phase { IDLE, PLAYING, CANCELLING }

const STORY_PATH_PREFIX := "res://data/stories/"
const MOVE_TIMEOUT_SECONDS := 12.0
const STORY_TIMEOUT_SECONDS := 180.0
const MOVE_ARRIVAL_TOLERANCE := 1.0
const PAUSE_MIN := 0.1
const PAUSE_MAX := 5.0
const StoryWorldBridgeScript := preload("res://scripts/directing/story_world_bridge.gd")
const StoryCollisionGuardScript := preload("res://scripts/directing/story_collision_guard.gd")

var _phase: Phase = Phase.IDLE
var _current_story: Dictionary = {}
var _beat_index: int = 0
var _cast_ids: Array = []
var _cast_nodes: Dictionary = {}
var _last_error: String = ""
var _story_elapsed: float = 0.0
var _run_epoch: int = 0
var _did_pause_autonomy: bool = false
var _autonomy_was_enabled: bool = false
var _world_bridge := StoryWorldBridgeScript.new()
var _collision_guard := StoryCollisionGuardScript.new()


## [D1] 注册到场景树，设置常驻处理模式，连接剧情请求信号。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if MessageBus.has_signal("story_requested"):
		MessageBus.story_requested.connect(_on_story_requested)


## [D1] 处理玩家 !剧情 / !story 命令：解析 story_id 并启动播放。
## 侧效：通过 ui_status_changed 反馈启动结果。
func _on_story_requested(story_id: String) -> void:
	var result := play_story(story_id)
	if result != 0:
		MessageBus.ui_status_changed.emit(
			"剧情启动失败: %s" % _last_error, "error"
		)
	else:
		MessageBus.ui_status_changed.emit(
			"剧情已启动: %s" % story_id, "playing"
		)


## [D1] 播放指定 story_id 的剧本：加载文件，验证，委托同步初始化并异步执行。
## 返回 0 表示成功启动，非 0 表示错误。
func play_story(story_id: String) -> int:
	if _phase != Phase.IDLE:
		_last_error = "已有剧情正在播放: %s" % _current_story.get("title", _current_story.get("story_id", "unknown"))
		return 1
	var path := STORY_PATH_PREFIX + story_id + ".json"
	if not FileAccess.file_exists(path):
		_last_error = "剧本文件不存在: %s" % path
		return 2
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		_last_error = "无法读取剧本文件: %s" % path
		return 3
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_last_error = "剧本 JSON 解析失败: %s" % path
		return 4
	return play_story_document(parsed)


## [D1] 播放一个剧本 Dictionary：通过 registry 获取允许角色列表创建 validator，
## 校验后暂停自主调度、中断 cast、启动异步执行。
## 返回 0 表示成功启动，非 0 表示校验失败。
func play_story_document(document: Dictionary) -> int:
	if _phase != Phase.IDLE:
		_last_error = "已有剧情正在播放: %s" % _current_story.get("title", _current_story.get("story_id", "unknown"))
		return 1
	_last_error = ""  # 成功启动前清空上次错误
	var allowed_cast := _world_bridge.get_registry_cast()
	var ValidatorScript = load("res://scripts/directing/story_schema_validator.gd")
	var validator = ValidatorScript.new(allowed_cast)
	if not validator.validate(document):
		var errors = validator.get_errors()
		if not errors.is_empty():
			_last_error = errors[0]["message"]
		else:
			_last_error = "剧本校验失败"
		return 5
	_current_story = validator.normalize(document)
	_cast_ids = _current_story["cast"].duplicate(true)
	_cast_nodes.clear()
	_beat_index = 0
	_story_elapsed = 0.0
	_run_epoch += 1  # 新 run epoch，使旧异步栈失效
	_did_pause_autonomy = false
	_phase = Phase.PLAYING
	if _resolve_cast_nodes():
		_collision_guard.enable(
			_cast_nodes, _cast_ids, get_tree().get_nodes_in_group("agents")
		)
		_pause_autonomy()
		_interrupt_cast()
		MessageBus.story_started.emit(
			String(_current_story.get("story_id", "")), _cast_ids.duplicate()
		)
		call_deferred("_execute_story")
		return 0
	else:
		_last_error = "无法解析演出角色节点"
		_finish_story(false, "cast_resolution_failed")
		return 6


## [D1][D2] 取消当前故事：立即使当前 run epoch 失效，取消 cast 动作后统一清理。
## 取消后旧异步栈不得再发出对白、cue 或剧情记忆。
func cancel_story(reason: String) -> void:
	if _phase != Phase.PLAYING:
		return
	_run_epoch += 1  # 立即使当前 run 的旧 epoch 失效
	_phase = Phase.CANCELLING
	for actor_id in _cast_ids:
		var agent: Node3D = _cast_nodes.get(actor_id)
		if is_instance_valid(agent) and agent.has_method("cancel_movement"):
			agent.cancel_movement("story_cancelled")
		MessageBus.emit_actions.emit(actor_id, [])
	_finish_story(false, "cancelled: %s" % reason)


## [D1][D2] 返回诊断状态快照，不修改内部状态。
func get_diagnostics() -> Dictionary:
	var diag: Dictionary = {
		"phase": _phase,
		"status": Phase.keys()[_phase],
		"story_title": _current_story.get("title", ""),
		"story_id": _current_story.get("story_id", ""),
		"beat_index": _beat_index,
		"total_beats": len(_current_story.get("beats", [])),
		"last_error": _last_error,
		"run_epoch": _run_epoch,
	}
	return diag


## [D2][T4.5] 主演出循环：顺序执行每个 beat，每个异步步骤后校验 run epoch。
## 注意：不捕捉额外参数；run epoch 从 _run_epoch 读取以确保取消后立即失效。
func _execute_story() -> void:
	var epoch: int = _run_epoch
	var beats: Array = _current_story.get("beats", [])
	while _beat_index < beats.size() and _phase == Phase.PLAYING:
		if epoch != _run_epoch:
			return
		var beat: Dictionary = beats[_beat_index]
		var success := await _execute_beat(_beat_index, beat, epoch)
		if epoch != _run_epoch:
			return
		if not success or _phase != Phase.PLAYING:
			return
		_beat_index += 1
		_story_elapsed += float(beat.get("pause_after", 1.5))
		if _story_elapsed > STORY_TIMEOUT_SECONDS:
			if epoch == _run_epoch:
				_finish_story(false, "story_timeout")
			return
	if epoch == _run_epoch and _phase == Phase.PLAYING:
		_finish_story(true, "completed")


## [D2][S3.2][T4.5] 执行单个 beat：走位→注视→物体交互→cue→对白→停顿。
## 每个 await 后校验 epoch，取消后不得继续执行。
## 成功返回 true，失败调用 _finish_story 并返回 false。
func _execute_beat(index: int, beat: Dictionary, epoch: int) -> bool:
	var actor_id := String(beat["actor"])
	var agent: Node3D = _cast_nodes.get(actor_id)
	if not is_instance_valid(agent):
		if epoch == _run_epoch:
			_finish_story(false, "角色节点已失效: %s" % actor_id)
		return false
	if String(agent.get("current_activity")) == "executing_actions":
		MessageBus.emit_actions.emit(actor_id, [])
		await get_tree().process_frame
		if epoch != _run_epoch:
			return false

	if beat.has("move_to"):
		if not await _move_actor_for_beat(actor_id, agent, beat["move_to"], epoch):
			return false

	if epoch != _run_epoch:
		return false
	MessageBus.story_beat_started.emit(index, beat.duplicate(true))
	if beat.has("look_at_actor"):
		var target_node: Node3D = _cast_nodes.get(String(beat["look_at_actor"]))
		if not is_instance_valid(target_node):
			if epoch == _run_epoch:
				_finish_story(false, "注视目标角色已失效: %s" % beat["look_at_actor"])
			return false
		agent.turn_towards_world_position(target_node.global_position, 0.3)
	elif beat.has("look_at_object"):
		agent.look_at_target(String(beat["look_at_object"]))

	if epoch != _run_epoch:
		return false
	if beat.has("interact"):
		var interaction_result: Dictionary = _world_bridge.perform_interaction(
			actor_id, beat["interact"]
		)
		if not bool(interaction_result.get("ok", false)):
			if epoch == _run_epoch:
				_finish_story(false, String(interaction_result.get("reason", "")))
			return false

	if epoch != _run_epoch:
		return false
	_emit_beat_performance(actor_id, beat)

	var pause := _world_bridge.recommended_pause(
		beat, clampf(float(beat.get("pause_after", 1.5)), PAUSE_MIN, PAUSE_MAX)
	)
	await _safe_wait(pause, epoch)
	return epoch == _run_epoch


## [D2] 向指定角色发送动作、表情与对白表现提示。
func _emit_beat_performance(actor_id: String, beat: Dictionary) -> void:
	if beat.has("gesture"):
		MessageBus.performance_cue.emit(String(beat["gesture"]), {
			"agent_id": actor_id,
			"source": "story_director",
			"story_id": _current_story.get("story_id", ""),
		})
	if beat.has("expression"):
		MessageBus.expression_cue.emit(String(beat["expression"]), 0.7, {
			"agent_id": actor_id,
			"source": "story_director",
		})
	if beat.has("say"):
		MessageBus.route_agent_output(
			actor_id,
			String(beat["say"]),
			String(beat.get("expression", "neutral")),
		)


## [D2][T4.5] 解析并执行单个 Beat 的安全走位，取消时立即返回。
func _move_actor_for_beat(
	actor_id: String,
	agent: Node3D,
	move_to: Dictionary,
	epoch: int
) -> bool:
	var target_pos := _world_bridge.resolve_move_target(move_to)
	if target_pos == Vector3.INF:
		if epoch == _run_epoch:
			_finish_story(false, "无法解析走位目标: %s" % var_to_str(move_to))
		return false
	agent.move_to_position(target_pos)
	var move_ok := await _await_move(actor_id, agent, target_pos, epoch)
	return epoch == _run_epoch and move_ok


## [D2][T4.5] 轮询 Agent 移动状态并验证最终距离，避免局部闭包状态失联。
func _await_move(actor_id: String, agent: Node3D, target: Vector3, epoch: int) -> bool:
	var started := Time.get_ticks_msec()
	while is_instance_valid(agent) and bool(agent.get("is_moving")):
		if epoch != _run_epoch:
			return false
		var elapsed := float(Time.get_ticks_msec() - started) / 1000.0
		if elapsed > MOVE_TIMEOUT_SECONDS:
			agent.cancel_movement("story_timeout")
			if epoch == _run_epoch:
				_finish_story(false, "走位超时: %s" % actor_id)
			return false
		if not is_instance_valid(agent):
			if epoch == _run_epoch:
				_finish_story(false, "走位中途角色已失效: %s" % actor_id)
			return false
		await get_tree().process_frame

	if not is_instance_valid(agent) or agent.global_position.distance_to(target) > MOVE_ARRIVAL_TOLERANCE:
		if epoch == _run_epoch:
			var distance := (
				agent.global_position.distance_to(target)
				if is_instance_valid(agent) else INF
			)
			_finish_story(false, "走位未到达: %s beat=%d target=%s distance=%.2f" % [
				actor_id, _beat_index, target, distance,
			])
		return false
	return true


## [D2][T4.5] 安全等待：每帧检查 epoch，取消后立即终止。
func _safe_wait(seconds: float, epoch: int) -> void:
	var elapsed := 0.0
	while elapsed < seconds and _phase == Phase.PLAYING:
		if epoch != _run_epoch:
			return
		await get_tree().process_frame
		elapsed += get_process_delta_time()


## [D1] 从场景树解析 cast 角色节点。返回 true 表示全部找到。
func _resolve_cast_nodes() -> bool:
	_cast_nodes.clear()
	var all_agents := get_tree().get_nodes_in_group("agents")
	if all_agents.is_empty():
		_last_error = "场景中没有角色节点"
		return false
	var found: Dictionary = {}
	for agent in all_agents:
		var name := String(agent.get("agent_name"))
		if not name.is_empty():
			found[name] = agent
	for id in _cast_ids:
		if found.has(id):
			_cast_nodes[id] = found[id]
		else:
			_last_error = "找不到角色节点: %s" % id
			return false
	return true


## [D2] 暂停自主调度并记录调度器原始状态。
## cast 解析失败不会调用此函数，因此不会错误修改自主调度。
func _pause_autonomy() -> void:
	if has_node("/root/AutonomousBehaviorSystem"):
		var autonomy := get_node("/root/AutonomousBehaviorSystem")
		# 通过属性访问记录原始值，避免向超预算文件中新增公开 getter
		_autonomy_was_enabled = autonomy.get("_scheduler_enabled") if autonomy else true
		autonomy.set_scheduler_enabled(false)
		_did_pause_autonomy = true


## [D2] 唯一恢复入口：只在确实暂停过自主调度时恢复原值。
func _restore_autonomy() -> void:
	if not _did_pause_autonomy:
		return
	_did_pause_autonomy = false
	if has_node("/root/AutonomousBehaviorSystem"):
		var autonomy := get_node("/root/AutonomousBehaviorSystem")
		if _autonomy_was_enabled:
			autonomy.set_scheduler_enabled(true)


## [D1] 打断所有 cast 成员的当前动作队列。
func _interrupt_cast() -> void:
	for actor_id in _cast_ids:
		MessageBus.agent_activity_interrupted.emit(actor_id, "", "story_director")
		MessageBus.emit_actions.emit(actor_id, [])


## [D2][T4.5] 统一幂等清理：成功时写剧情记忆和清空 last_error；
## 失败/取消保留 last_error；恢复自主调度原值；重置 run 状态。
## 取消后禁止写剧情记忆。
func _finish_story(success: bool, reason: String) -> void:
	if success:
		_write_story_memory()
		_last_error = ""  # 成功后 last_error 为空
	else:
		_last_error = reason
	MessageBus.story_finished.emit(success, reason)
	_collision_guard.restore_safely(
		_cast_nodes, _cast_ids, get_tree().get_nodes_in_group("agents")
	)
	_cast_nodes.clear()
	_current_story = {}
	_beat_index = 0
	_restore_autonomy()
	_phase = Phase.IDLE


## [D2] 向每个 cast 成员写入带 [剧情] 标记的记忆总结。
## 侧效：通过 MemorySystem.add_episode_for_agent 持久化。
func _write_story_memory() -> void:
	var summary := String(_current_story.get("memory_summary", "完成了一场剧情演出。"))
	var content := "[剧情] %s" % summary
	if has_node("/root/MemorySystem"):
		var memory := get_node("/root/MemorySystem")
		for actor_id in _cast_ids:
			memory.add_episode_for_agent(actor_id, content, 7.0)
