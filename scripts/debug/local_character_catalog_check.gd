# Roadmap: C6.2, C2.2, C3.2, C5.1, D2, O4
# Responsibility: 验证本地 Q 版角色目录可同时生成多名独立 Agent，并分别响应
# 点名、动作、表情、剧情和记忆；本地受限资产缺失时安全跳过。
# Tests: 本文件为 Godot headless 运行时验收。

extends SceneTree

const LOCAL_ROLES := [
	{
		"id": "castorice_agent",
		"name": "遐蝶",
		"node": "CastoriceAgent",
		"model": "res://assets/local_characters/castorice/castorice.glb",
		"surprised_morph": "驚き",
		"sad_morph": "悲しい",
		"shy_morph": "なごみ",
	},
	{
		"id": "cartethyia_agent",
		"name": "卡提希娅",
		"node": "CartethyiaAgent",
		"model": "res://assets/local_characters/cartethyia/cartethyia.glb",
		"surprised_morph": "びっくり",
		"sad_morph": "困る",
		"shy_morph": "照れ2",
	},
	{
		"id": "xiangliyao_agent",
		"name": "相里要",
		"node": "XiangliyaoAgent",
		"model": "res://assets/local_characters/xiangliyao/xiangliyao.glb",
		"surprised_morph": "びっくり",
		"sad_morph": "困る",
		"shy_morph": "照れ2",
	},
]

var _available_roles: Array[Dictionary] = []


## [C6.2][O4] 延迟运行，使 Autoload 先完成初始化。
func _init() -> void:
	call_deferred("_run")


## [C6.2][C2.2][C3.2][C5.1][D2] 验证多角色本地目录闭环。
func _run() -> void:
	for role in LOCAL_ROLES:
		if ResourceLoader.exists(String(role.model)):
			_available_roles.append(role)
	if _available_roles.is_empty():
		print("LOCAL_CHARACTER_CATALOG_SKIP no local licensed assets")
		quit(0)
		return
	root.get_node("ExperienceModeManager").enter_performance_mode()
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	await _verify_each_role(scene)
	var story_result: int = root.get_node("StoryDirector").play_story_document(_story_document())
	_assert(story_result == 0, "multi-role story was rejected")
	await _wait_for_story(9000)
	_verify_independent_memories()
	print("LOCAL_CHARACTER_CATALOG_PASS actors=%d" % _available_roles.size())
	root.get_node("AutonomousBehaviorSystem").set_scheduler_enabled(false)
	scene.free()
	quit(0)


## [C6.2][C2.2][C3.2] 逐角色验证注册、显示名路由、骨骼和 Morph。
func _verify_each_role(scene: Node) -> void:
	var registry := root.get_node("CharacterAdapterRegistry")
	var bus := root.get_node("MessageBus")
	for role in _available_roles:
		var agent_id := String(role.id)
		var agent_path := "WorldRoot/LivingRoom/LocalCharacterSpawner/%s" % role.node
		var agent := scene.get_node_or_null(agent_path)
		_assert(agent != null, "%s was not spawned" % agent_id)
		_assert(agent_id in registry.get_registered_agent_ids(), "%s was not registered" % agent_id)
		_assert(
			bus._resolve_target_agent("@%s 你好" % role.name) == agent_id,
			"%s display-name targeting failed" % agent_id,
		)
		var overlay := agent.get_node("CharacterPoseOverlay")
		var bones: Dictionary = overlay.get_resolved_bone_names()
		_assert(
			bones.has("right_upper_arm") and bones.has("right_hand"),
			"%s MMD arm aliases unresolved" % agent_id,
		)
		var driver := agent.get_node("CharacterExpressionDriver")
		var morphs: PackedStringArray = driver.get_available_morph_names()
		_assert("笑い" in morphs and "まばたき" in morphs, "%s morph aliases missing" % agent_id)
		for key in ["surprised_morph", "sad_morph", "shy_morph"]:
			_assert(String(role[key]) in morphs, "%s missing %s" % [agent_id, role[key]])
		bus.performance_cue.emit("wave", {"agent_id": agent_id, "source": "catalog_test"})
		bus.expression_cue.emit("happy", 0.8, {"agent_id": agent_id, "source": "catalog_test"})
		await create_timer(0.22).timeout
		_assert(overlay.get_current_overlay_gesture() == "wave", "%s did not wave" % agent_id)
		_assert(_morph_value(agent, "笑い") > 0.3, "%s did not smile" % agent_id)
		await _verify_library_extensions(bus, agent, overlay, role)


## [C2.2][C3.2] 验证循环行走和模型专属惊讶、难过、害羞 Morph。
func _verify_library_extensions(bus: Node, agent: Node, overlay: Node, role: Dictionary) -> void:
	var agent_id := String(role.id)
	bus.performance_cue.emit("walk", {"agent_id": agent_id, "source": "catalog_test"})
	await create_timer(0.12).timeout
	_assert(overlay.get_current_overlay_gesture() == "walk", "%s walk overlay missing" % agent_id)
	bus.performance_cue.emit("idle", {"agent_id": agent_id, "source": "catalog_test"})
	await process_frame
	_assert(overlay.get_current_overlay_gesture() == "idle", "%s walk overlay did not stop" % agent_id)
	bus.expression_cue.emit("surprised", 0.8, {"agent_id": agent_id, "source": "catalog_test"})
	await create_timer(0.22).timeout
	_assert(_morph_value(agent, String(role.surprised_morph)) > 0.35, "%s surprise missing" % agent_id)
	bus.expression_cue.emit("sad", 0.8, {"agent_id": agent_id, "source": "catalog_test"})
	await create_timer(0.22).timeout
	_assert(_morph_value(agent, String(role.sad_morph)) > 0.35, "%s sad morph missing" % agent_id)
	bus.expression_blend_cue.emit({
		"expression": "shy_happy",
		"morph_weights": {"shy": 1.0},
		"intensity": 0.8,
		"fade_duration": 0.12,
	}, {"agent_id": agent_id, "source": "catalog_test"})
	await create_timer(0.16).timeout
	_assert(_morph_value(agent, String(role.shy_morph)) > 0.35, "%s shy morph missing" % agent_id)


## [D1][D2] 为当前存在的本地角色生成一场非写死角色数量的问候演出。
func _story_document() -> Dictionary:
	var cast: Array[String] = []
	var beats: Array[Dictionary] = []
	for role in _available_roles:
		cast.append(String(role.id))
		beats.append({
			"actor": String(role.id),
			"gesture": "wave",
			"expression": "happy",
			"say": "%s向大家挥手问好。" % role.name,
			"pause_after": 0.1,
		})
	return {
		"schema_version": 1,
		"story_id": "local_q_catalog",
		"title": "Q版伙伴见面会",
		"cast": cast,
		"beats": beats,
		"memory_summary": "本地Q版伙伴一起参加了客厅见面会。",
	}


## [D2][T4.5] 等待剧情导演完成，超时立即失败。
func _wait_for_story(timeout_msec: int) -> void:
	var started := Time.get_ticks_msec()
	var director := root.get_node("StoryDirector")
	while int(director.get_diagnostics().phase) != 0:
		if Time.get_ticks_msec() - started > timeout_msec:
			director.cancel_story("local_catalog_timeout")
			_assert(false, "multi-role story timed out")
			return
		await process_frame


## [C5.1][D2] 确认剧情总结分别写入每名角色自己的记忆分区。
func _verify_independent_memories() -> void:
	var memories: Dictionary = root.get_node("MemorySystem").agent_memories
	for role in _available_roles:
		var found := false
		for episode in memories.get(String(role.id), {}).get("episodes", []):
			if "本地Q版伙伴" in String(episode.get("content", "")):
				found = true
		_assert(found, "%s did not receive independent story memory" % role.id)


## [C3.2] 返回指定 MMD Morph 的当前权重。
func _morph_value(node: Node, morph_name: String) -> float:
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := child as MeshInstance3D
		for index in mesh_node.mesh.get_blend_shape_count():
			if String(mesh_node.mesh.get_blend_shape_name(index)) == morph_name:
				return mesh_node.get_blend_shape_value(index)
	return 0.0


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("LOCAL_CHARACTER_CATALOG_FAIL: %s" % message)
	quit(1)
	assert(condition, message)
