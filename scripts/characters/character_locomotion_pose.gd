# Roadmap: C2.3, C2.4
# Responsibility: 依据角色实际水平位移生成平滑的程序化步态相位与语义骨骼姿势；
#   不移动角色根节点、不选择路径，也不解析具体骨骼名称。
# Collaborators: CharacterPoseOverlay, CharacterAdapterRegistry
# Tests: scripts/debug/locomotion_quality_check.gd

class_name CharacterLocomotionPose
extends RefCounted

const DEFAULT_STRIDE_METERS := 1.05
const DEFAULT_BLEND_SECONDS := 0.18
const MOVEMENT_EPSILON_METERS := 0.001

var _stride_meters := DEFAULT_STRIDE_METERS
var _blend_seconds := DEFAULT_BLEND_SECONDS
var _phase_radians := 0.0
var _blend_weight := 0.0
var _last_position := Vector3.ZERO
var _has_last_position := false


## [C2.3] 读取动作适配器中的米制步态参数；无效值回退到安全默认值。
func configure(profile: Dictionary) -> void:
	_stride_meters = maxf(float(profile.get("stride_meters", DEFAULT_STRIDE_METERS)), 0.2)
	_blend_seconds = maxf(float(profile.get("blend_seconds", DEFAULT_BLEND_SECONDS)), 0.05)


## [C2.4] 用真实水平位移推进步态，并在停止或堵塞时平滑回到基准姿势。
## 返回值只包含语义骨骼旋转增量（度），不包含 root motion。
func sample(
	delta_seconds: float,
	world_position: Vector3,
	is_walk_requested: bool,
	walk_overlay: Dictionary,
) -> Dictionary:
	var distance_meters := _horizontal_distance(world_position, _last_position) if _has_last_position else 0.0
	_last_position = world_position
	_has_last_position = true
	var has_progress := is_walk_requested and distance_meters > MOVEMENT_EPSILON_METERS
	var target_weight := 1.0 if has_progress else 0.0
	_blend_weight = move_toward(
		_blend_weight,
		target_weight,
		delta_seconds / _blend_seconds,
	)
	if has_progress:
		_phase_radians = fposmod(
			_phase_radians + distance_meters / _stride_meters * TAU,
			TAU,
		)
	if _blend_weight <= 0.001 or walk_overlay.is_empty():
		return {}
	return _build_pose(walk_overlay)


## [C2.4] 返回累计步态相位，供确定性验收读取；纯读取。
func get_phase_radians() -> float:
	return _phase_radians


## [C2.4] 返回当前起停混合权重，供表现层诊断；纯读取。
func get_blend_weight() -> float:
	return _blend_weight


## [C2.4] 将行走 Profile 的周期通道组合为语义骨骼旋转。
func _build_pose(overlay: Dictionary) -> Dictionary:
	var result := {}
	var wave := sin(_phase_radians)
	var bounce := absf(sin(_phase_radians))
	_add_scaled(result, overlay.get("oscillate_degrees", {}), wave * _blend_weight)
	_add_scaled(result, overlay.get("positive_degrees", {}), maxf(wave, 0.0) * _blend_weight)
	_add_scaled(result, overlay.get("negative_degrees", {}), maxf(-wave, 0.0) * _blend_weight)
	_add_scaled(result, overlay.get("bounce_degrees", {}), bounce * _blend_weight)
	return result


## [C2.4] 把一组 Vector3 度数按相位权重累加到输出姿势。
func _add_scaled(target: Dictionary, channels: Variant, weight: float) -> void:
	if not channels is Dictionary:
		return
	for semantic_bone in channels:
		var value := _vec3(channels[semantic_bone]) * weight
		target[semantic_bone] = _vec3(target.get(semantic_bone, Vector3.ZERO)) + value


## [C2.4] 计算 XZ 平面的真实位移，忽略地面高度和模型上下摆动。
func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## [C2.3] 将 Profile 数组转换为旋转向量；无效输入安全归零。
func _vec3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
