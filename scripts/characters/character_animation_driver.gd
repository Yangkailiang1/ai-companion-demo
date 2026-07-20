# character_animation_driver.gd — 独立角色表现适配器
# 负责监听 performance cue 信号，驱动 AnimationPlayer 播放对应动画。
# CognitiveCycle/ActionExecutor 不直接操作 AnimationPlayer，
# 而是通过此适配器间接控制角色表现。
#
# 数据流:
#   ActionExecutor/AgentBase → MessageBus.performance_cue → CharacterAnimationDriver
#   → AnimationPlayer.play() / cross_fade

extends Node

# --- 导出配置 ---
@export var animation_player: AnimationPlayer
@export var cross_fade_duration: float = 0.2
@export var default_animation: String = "idle"

# --- 状态 ---
var current_gesture: int = PerformanceCueTypes.Gesture.IDLE
var pending_gesture_queue: Array[String] = []
var _is_talking: bool = false
const LOOPING_GESTURES := ["idle", "walk"]

# Sound/vocal hook (placeholder for future audio)
signal gesture_changed(old_gesture: String, new_gesture: String)

# --- 生命周期 ---

func _ready():
	# 监听 performance cue 信号
	if not MessageBus.has_signal("performance_cue"):
		push_warning("CharacterAnimationDriver: performance_cue signal not found on MessageBus")
	else:
		MessageBus.performance_cue.connect(_on_performance_cue)

	if not animation_player:
		animation_player = _find_animation_player()
		if not animation_player:
			push_warning("CharacterAnimationDriver: no AnimationPlayer found — animations disabled")

	if animation_player and not animation_player.animation_finished.is_connected(_on_animation_finished):
		animation_player.animation_finished.connect(_on_animation_finished)

	# 初始播放 idle
	_play_animation(default_animation)


func _find_animation_player() -> AnimationPlayer:
	# 从 Agent 的整个子树查找（导入的 GLB 自带 AnimationPlayer）。
	var parent = get_parent()
	if not parent:
		return null
	return _find_animation_player_recursive(parent)


func _find_animation_player_recursive(node: Node) -> AnimationPlayer:
	for child in node.get_children():
		if child is AnimationPlayer:
			return child
		var nested = _find_animation_player_recursive(child)
		if nested:
			return nested
	return null


# --- 核心：接收 cue 信号 ---

func _on_performance_cue(gesture_name: String, context: Dictionary) -> void:
	if not animation_player:
		return

	# 校验 gesture
	var gesture_str = gesture_name.to_lower()
	if not PerformanceCueTypes.is_valid_gesture(gesture_str):
		push_warning("CharacterAnimationDriver: unknown gesture '%s', ignoring" % gesture_name)
		return

	# 特殊处理：talk cue
	if gesture_str == "talk":
		_is_talking = true
		# Talk 使用 idle 动画 + 可能的 future 嘴部 blend
		# 本轮 talk 使用 idle 作为基础动画
		_play_animation("idle", cross_fade_duration)
		return

	_is_talking = false

	# 检查动画是否存在
	if not animation_player.has_animation(gesture_str):
		push_warning("CharacterAnimationDriver: animation '%s' not found in AnimationPlayer, falling back to idle" % gesture_str)
		_play_animation("idle", cross_fade_duration)
		gesture_str = "idle"

	_play_animation(gesture_str, cross_fade_duration)


# --- 内部 ---

func _play_animation(name: String, blend_time: float = 0.2) -> void:
	if not animation_player or not animation_player.has_animation(name):
		return

	var old = PerformanceCueTypes.gesture_to_string(current_gesture)
	current_gesture = PerformanceCueTypes.parse_gesture(name)

	if animation_player.current_animation != name:
		animation_player.play(name, blend_time)
		gesture_changed.emit(old, name)


func _on_animation_finished(animation_name: StringName) -> void:
	if String(animation_name) in LOOPING_GESTURES:
		# Some GLTF importers do not preserve Blender's cyclic flag. Restart the
		# two locomotion loops explicitly so the character never freezes.
		animation_player.play(animation_name)
	else:
		_play_animation(default_animation, cross_fade_duration)


# 停止动画（用于 disable）
func stop() -> void:
	if animation_player and animation_player.is_playing():
		animation_player.stop()


# 获取当前播放的 gesture
func get_current_gesture() -> String:
	return PerformanceCueTypes.gesture_to_string(current_gesture)


# 是否正在播放指定 gesture
func is_playing(gesture_name: String) -> bool:
	if not animation_player:
		return false
	return animation_player.current_animation == gesture_name and animation_player.is_playing()
