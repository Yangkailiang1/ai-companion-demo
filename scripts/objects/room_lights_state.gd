# Roadmap: S3.3, C4.4
# Responsibility: 客厅壁灯的开关、调光、语义状态和可见光照反馈。
# Collaborators: InteractableObject, SemanticWorld
# Tests: scripts/debug/physics_interaction_check.gd

extends Node

var _lights: Array[OmniLight3D] = []
var _glows: Array[MeshInstance3D] = []


## [S3.3] 收集客厅壁灯并按存档中的语义状态刷新。
func _ready() -> void:
	var room := get_parent().get_parent()
	for node_name in ["LeftSconceLight", "RightSconceLight"]:
		var light := room.get_node_or_null(node_name) as OmniLight3D
		if light:
			_lights.append(light)
	for node_name in ["LeftWallLampGlow", "RightWallLampGlow"]:
		var glow := room.get_node_or_null(node_name) as MeshInstance3D
		if glow:
			_glows.append(glow)
	call_deferred("_sync_from_semantic_state")


## [S3.3][D2] 执行开灯、关灯和调暗，并产生实际光照变化。
func perform_interaction(verb: String, _actor_id: String = "") -> Dictionary:
	var state := ""
	var energy := 0.0
	match verb:
		"turn_on":
			state = "暖光已开启"
			energy = 0.65
		"dim":
			state = "柔和夜灯"
			energy = 0.22
		"turn_off":
			state = "关闭"
		_:
			return {"handled": false}
	_apply_energy(energy)
	SemanticWorld.update_object_state("room_lights", state)
	return {"handled": true, "success": true, "state": state}


## [S3.3] 从语义状态恢复灯光。
func _sync_from_semantic_state() -> void:
	var object = SemanticWorld.get_object("room_lights")
	if object == null:
		return
	var state := String(object.state)
	_apply_energy(0.0 if state == "关闭" else (0.22 if state == "柔和夜灯" else 0.65))


## [S3.3] 同步真实 OmniLight 与灯罩发光可见性。
func _apply_energy(energy: float) -> void:
	for light in _lights:
		light.light_energy = energy
	for glow in _glows:
		glow.visible = energy > 0.0
