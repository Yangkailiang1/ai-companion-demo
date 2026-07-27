# Roadmap: S3.2, D2
# Responsibility: 电视机的可持久化开关/频道状态与屏幕视觉反馈。
# Collaborators: InteractableObject, SemanticWorld, MessageBus
# Tests: scripts/debug/story_director_check.gd

extends Node

@onready var _screen: MeshInstance3D = get_parent().get_node_or_null("TVScreenGlow")


## [S3.2] 初始化屏幕显示，并监听存档恢复或外部电视状态变化。
func _ready() -> void:
	MessageBus.world_state_changed.connect(_on_world_state_changed)
	call_deferred("_sync_from_semantic_state")


## [S3.2][D2] 执行电视白名单交互并同步语义状态与可见反馈。
func perform_interaction(verb: String, _actor_id: String = "") -> Dictionary:
	var new_state := ""
	match verb:
		"turn_on", "watch":
			new_state = "播放温馨节目"
		"change_channel":
			new_state = "播放轻松动画"
		"turn_off":
			new_state = "关闭"
		_:
			return {"handled": false}
	SemanticWorld.update_object_state("tv", new_state)
	_apply_screen_state(new_state != "关闭")
	return {"handled": true, "state": new_state}


## [S3.2][X1] 存档载入或电视状态变化后刷新屏幕，不反向改写语义状态。
func _on_world_state_changed(change_type: String, data: Dictionary) -> void:
	if change_type == "save_loaded":
		_sync_from_semantic_state()
	elif change_type == "object_state_changed" and String(data.get("object_id", "")) == "tv":
		_apply_screen_state(String(data.get("new_state", "关闭")) != "关闭")


## [S3.2] 从 SemanticWorld 获取电视当前状态。
func _sync_from_semantic_state() -> void:
	var tv = SemanticWorld.get_object("tv")
	_apply_screen_state(tv != null and String(tv.state) != "关闭")


## [S1][S3.2] 切换电视屏幕覆盖层，提供清晰的开关机视觉反馈。
func _apply_screen_state(powered: bool) -> void:
	if not is_instance_valid(_screen):
		return
	_screen.visible = powered
	if not powered:
		return
	var material := _screen.get_active_material(0)
	if material is StandardMaterial3D:
		var local_material := material.duplicate() as StandardMaterial3D
		local_material.albedo_color = Color(0.22, 0.48, 0.72, 1.0)
		local_material.emission = Color(0.18, 0.52, 0.9, 1.0)
		local_material.emission_energy_multiplier = 1.35
		_screen.material_override = local_material
