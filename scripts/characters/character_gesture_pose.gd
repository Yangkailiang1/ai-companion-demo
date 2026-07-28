# Roadmap: C2.1, C2.3
# Responsibility: 将单次语义手势 Profile 采样为骨骼旋转增量；
#   不保存角色状态、不解析骨骼，也不处理循环行走。
# Collaborators: CharacterPoseOverlay
# Tests: scripts/debug/multi_agent_check.gd

class_name CharacterGesturePose
extends RefCounted


## [C2.1][C2.3] 在归一化时间采样手势的固定与振荡旋转通道。
static func sample(overlay: Dictionary, normalized_time: float) -> Dictionary:
	if overlay.is_empty():
		return {}
	var result := {}
	var envelope := 1.0 if bool(overlay.get("continuous", false)) else sin(normalized_time * PI)
	var wave := sin(normalized_time * TAU * float(overlay.get("cycles", 1.0)))
	for semantic_bone in overlay.get("degrees", {}):
		result[semantic_bone] = _vec3(overlay["degrees"][semantic_bone]) * envelope
	for semantic_bone in overlay.get("oscillate_degrees", {}):
		result[semantic_bone] = (
			_vec3(overlay["oscillate_degrees"][semantic_bone]) * envelope * wave
		)
	return result


## [C2.3] 将 Profile 数组转换为旋转向量；无效输入安全归零。
static func _vec3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
