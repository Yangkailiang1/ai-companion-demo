# Roadmap: C2.2, C3.2, C6.2, C8.1
# Responsibility: 近景渲染可选本地角色的挥手与开心表情，用于动作视觉验收。
# Tests: Run with Godot --path . --script <this file>.

extends SceneTree

const AGENT_PATH := "WorldRoot/LivingRoom/LocalCharacterSpawner/CastoriceAgent"
const OUTPUT_PATH := "/private/tmp/castorice_performance_preview.png"


func _init() -> void:
	call_deferred("_run")


## [C2.2][C3.2][C8.1] 播放挥手/开心提示并用近景相机截图。
func _run() -> void:
	root.size = Vector2i(900, 700)
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	if not scene.has_node(AGENT_PATH):
		print("LOCAL_CHARACTER_PERFORMANCE_PREVIEW_SKIP")
		quit(0)
		return
	var agent := scene.get_node(AGENT_PATH) as Node3D
	var camera := root.get_viewport().get_camera_3d()
	camera.global_position = agent.global_position + Vector3(1.8, 1.2, 2.3)
	camera.look_at(agent.global_position + Vector3(0, 0.68, 0), Vector3.UP)
	var bus := root.get_node("MessageBus")
	bus.performance_cue.emit("wave", {"agent_id": "castorice_agent", "source": "preview"})
	bus.expression_cue.emit("happy", 0.82, {
		"agent_id": "castorice_agent",
		"source": "preview",
	})
	await create_timer(0.42).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		push_error("LOCAL_CHARACTER_PERFORMANCE_PREVIEW_FAIL error=%d" % error)
		quit(1)
		return
	print("LOCAL_CHARACTER_PERFORMANCE_PREVIEW_PASS path=%s" % OUTPUT_PATH)
	quit(0)
