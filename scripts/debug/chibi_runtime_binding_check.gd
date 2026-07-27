# Roadmap: C6.2, C2.1, C3.1, D1
# Responsibility: 验证 Q 版 manifest 可动态加入动作/表情注册表和剧情 cast 白名单。
# Tests: 本文件为 Godot headless 合同验收。
# Verifies: C6.2, C2.1, C3.1, D1

extends SceneTree

const MANIFEST_PATH := "res://data/examples/chibi_character_manifest.example.json"


## [C6.2] 延迟启动运行时角色注册验收。
func _init() -> void:
	call_deferred("_run")


## [C6.2][C2.1][C3.1][D1] 注册示例 Q 版角色并验证共享语义映射。
func _run() -> void:
	var registry := root.get_node("CharacterAdapterRegistry")
	var fixture := _create_late_driver_fixture()
	var agent_root: Node3D = fixture["agent_root"]
	var animation_driver: Node = fixture["animation_driver"]
	var expression_driver: Node = fixture["expression_driver"]
	await process_frame
	_assert(animation_driver.get("_motion_adapter_type") == "procedural_root_fallback",
		"pre-registration driver did not use safe fallback")
	var binding := CharacterRuntimeBinding.new()
	agent_root.add_child(binding)
	_assert(binding.register_manifest(MANIFEST_PATH), binding.get_last_error())
	await process_frame
	_assert("future_chibi" in registry.get_registered_agent_ids(), "Q character missing from cast registry")
	_assert(registry.map_clip("future_chibi", "wave") == "wave", "shared wave was not mapped")
	_assert(registry.map_clip("future_chibi", "sit") == "sit", "shared sit was not mapped")
	_assert(animation_driver.get("_motion_adapter_type") == "animation_player",
		"late manifest did not refresh motion driver")
	var channels: Dictionary = registry.get_expression_channel_map("future_chibi")
	_assert("joy" in channels and "blink" in channels, "expression library channels were not mapped")
	_assert(expression_driver.get("_channel_aliases").has("joy"),
		"late manifest did not refresh expression driver")
	var prompt_builder = load("res://scripts/directing/story_planning_prompt_builder.gd").new()
	var prompt: String = prompt_builder.build("未来Q版角色向大家挥手。")
	_assert("future_chibi" in prompt and "未来Q版角色" in prompt, "Q character missing from LLM cast context")
	agent_root.queue_free()
	await process_frame
	_assert("future_chibi" not in registry.get_registered_agent_ids(), "removed Q character stayed in cast registry")
	print("CHIBI_RUNTIME_BINDING_PASS actions=8 expressions=%d" % channels.size())
	quit(0)


## [C6.2][C2.1][C3.1] 创建先于 manifest 进入树的动作/表情驱动验收夹具。
func _create_late_driver_fixture() -> Dictionary:
	var agent_root := Node3D.new()
	var animation_driver = load("res://scripts/characters/character_animation_driver.gd").new()
	animation_driver.agent_id = "future_chibi"
	animation_driver.procedural_root = agent_root
	var expression_driver = load("res://scripts/characters/expression_driver.gd").new()
	expression_driver.agent_id = "future_chibi"
	agent_root.add_child(animation_driver)
	agent_root.add_child(expression_driver)
	root.add_child(agent_root)
	return {
		"agent_root": agent_root,
		"animation_driver": animation_driver,
		"expression_driver": expression_driver,
	}


## [C6.2] 失败时返回非零退出码并保留具体合同错误。
func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("CHIBI_RUNTIME_BINDING_FAIL: %s" % message)
	quit(1)
	assert(condition, message)
