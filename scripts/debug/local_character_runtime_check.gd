# Roadmap: C6.2, C2.2, C3.2, C5.1, D2, O4
# Responsibility: 验证可选本地 Q 角色的动态注册、点名、骨骼动作、表情 Morph、
# 独立记忆和剧情闭环；资产缺失时安全跳过。
# Tests: 本文件为 Godot headless 运行时验收。

extends SceneTree

const AGENT_PATH := "WorldRoot/LivingRoom/LocalCharacterSpawner/CastoriceAgent"
const MODEL_PATH := "res://assets/local_characters/castorice/castorice.glb"
const AGENT_ID := "castorice_agent"


## [C6.2][O4] 延迟启动，并允许不包含本地受限资产的开源检出安全跳过。
func _init() -> void:
	call_deferred("_run")


## [C6.2][C2.2][C3.2][C5.1][D2] 验证本地角色完整演出链。
func _run() -> void:
	if not ResourceLoader.exists(MODEL_PATH):
		print("LOCAL_CHARACTER_RUNTIME_SKIP path=%s" % MODEL_PATH)
		quit(0)
		return
	root.get_node("ExperienceModeManager").enter_performance_mode()
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var agent := scene.get_node(AGENT_PATH)
	_verify_registration_and_targeting(agent)
	_send_performance_cues(agent)
	await create_timer(0.24).timeout
	_verify_performance_state(agent)
	_assert(
		root.get_node("StoryDirector").play_story_document(_story_document()) == 0,
		"StoryDirector rejected local Q story",
	)
	await _wait_for_story(6000)
	_assert(_has_story_memory(), "local Q role did not receive independent memory")
	print("LOCAL_CHARACTER_RUNTIME_PASS actor=%s morphs=37" % AGENT_ID)
	root.get_node("AutonomousBehaviorSystem").set_scheduler_enabled(false)
	scene.free()
	quit(0)


## [C6.2][D3] 检查运行时 cast、独立身份及通用 @显示名 路由。
func _verify_registration_and_targeting(agent: Node) -> void:
	var registry := root.get_node("CharacterAdapterRegistry")
	_assert(AGENT_ID in registry.get_registered_agent_ids(), "local Q role missing from cast")
	_assert(
		root.get_node("MessageBus")._resolve_target_agent("@遐蝶 你好") == AGENT_ID,
		"dynamic display-name targeting failed",
	)
	_assert(
		"安静、温柔" in root.get_node("CodifiedProfile").get_identity_for_agent(AGENT_ID),
		"manifest identity did not reach cognition",
	)
	var overlay := agent.get_node("CharacterPoseOverlay")
	var bones: Dictionary = overlay.get_resolved_bone_names()
	_assert(bones.has("right_upper_arm") and bones.has("right_hand"), "MMD arm aliases unresolved")


## [C2.2][C3.2] 向独立角色发送挥手和开心表情提示。
func _send_performance_cues(agent: Node) -> void:
	var driver := agent.get_node("CharacterExpressionDriver")
	var morphs: PackedStringArray = driver.get_available_morph_names()
	_assert("笑い" in morphs and "まばたき" in morphs, "MMD expression morphs undiscovered")
	var bus := root.get_node("MessageBus")
	bus.performance_cue.emit("wave", {"agent_id": AGENT_ID, "source": "test"})
	bus.expression_cue.emit("happy", 0.8, {"agent_id": AGENT_ID, "source": "test"})


## [C2.2][C3.2] 验证动作 Overlay 与笑容 Morph 确实作用到模型。
func _verify_performance_state(agent: Node) -> void:
	var overlay := agent.get_node("CharacterPoseOverlay")
	_assert(overlay.get_current_overlay_gesture() == "wave", "wave did not reach MMD overlay")
	_assert(_morph_value(agent, "笑い") > 0.35, "happy cue did not drive MMD smile")


## [C3.2] 返回指定原始 BlendShape 的当前权重。
func _morph_value(node: Node, morph_name: String) -> float:
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := child as MeshInstance3D
		for index in mesh_node.mesh.get_blend_shape_count():
			if String(mesh_node.mesh.get_blend_shape_name(index)) == morph_name:
				return mesh_node.get_blend_shape_value(index)
	return 0.0


## [D1][D2] 构造无需预制剧情文件的本地 Q 角色问候。
func _story_document() -> Dictionary:
	return {
		"schema_version": 1,
		"story_id": "local_q_runtime",
		"title": "遐蝶的问候",
		"cast": [AGENT_ID],
		"beats": [{
			"actor": AGENT_ID,
			"gesture": "wave",
			"expression": "happy",
			"say": "很高兴在客厅见到大家。",
			"pause_after": 0.15,
		}],
		"memory_summary": "遐蝶第一次在客厅向大家挥手问好。",
	}


## [D2][T4.5] 等待剧情导演完成，超时立即失败。
func _wait_for_story(timeout_msec: int) -> void:
	var started := Time.get_ticks_msec()
	var director := root.get_node("StoryDirector")
	while int(director.get_diagnostics().phase) != 0:
		if Time.get_ticks_msec() - started > timeout_msec:
			director.cancel_story("local_q_timeout")
			_assert(false, "local Q story timed out")
			return
		await process_frame


## [C5.1][D2] 仅在本角色记忆分区查找剧情总结。
func _has_story_memory() -> bool:
	var memory := root.get_node("MemorySystem")
	for episode in memory.agent_memories.get(AGENT_ID, {}).get("episodes", []):
		if "第一次在客厅" in String(episode.get("content", "")):
			return true
	return false


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("LOCAL_CHARACTER_RUNTIME_FAIL: %s" % message)
	quit(1)
	assert(condition, message)
