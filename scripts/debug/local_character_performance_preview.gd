# Roadmap: C2.2, C3.2, C6.2, C8.1
# Responsibility: 按参数近景渲染任一本地角色的动作与表情，用于视觉验收。
# Tests: Run with Godot --path . --script <this file>.

extends SceneTree

const DEFAULT_NODE_NAME := "CastoriceAgent"
const DEFAULT_AGENT_ID := "castorice_agent"
const DEFAULT_OUTPUT_PATH := "/private/tmp/castorice_performance_preview.png"


func _init() -> void:
	call_deferred("_run")


## [C2.2][C3.2][C8.1] 按 user args 播放动作/表情并用近景相机截图。
func _run() -> void:
	root.size = Vector2i(900, 700)
	var args := OS.get_cmdline_user_args()
	var node_name := String(args[0]) if args.size() > 0 else DEFAULT_NODE_NAME
	var agent_id := String(args[1]) if args.size() > 1 else DEFAULT_AGENT_ID
	var gesture := String(args[2]) if args.size() > 2 else "wave"
	var expression := String(args[3]) if args.size() > 3 else "happy"
	var output_path := String(args[4]) if args.size() > 4 else DEFAULT_OUTPUT_PATH
	var agent_path := "WorldRoot/LivingRoom/LocalCharacterSpawner/%s" % node_name
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	if not scene.has_node(agent_path):
		print("LOCAL_CHARACTER_PERFORMANCE_PREVIEW_SKIP path=%s" % agent_path)
		quit(0)
		return
	var agent := scene.get_node(agent_path) as Node3D
	for other in get_nodes_in_group("agents"):
		if other != agent and other is Node3D:
			(other as Node3D).visible = false
	agent.reparent(scene.get_node("WorldRoot"), false)
	agent.position = Vector3(0, 0, 5.0)
	agent.rotation = Vector3.ZERO
	var camera := root.get_viewport().get_camera_3d()
	camera.global_position = agent.global_position + Vector3(0, 0.95, 2.5)
	camera.look_at(agent.global_position + Vector3(0, 0.75, 0), Vector3.UP)
	camera.fov = 34.0
	var bus := root.get_node("MessageBus")
	bus.performance_cue.emit(gesture, {"agent_id": agent_id, "source": "preview"})
	bus.expression_cue.emit(expression, 0.82, {
		"agent_id": agent_id,
		"source": "preview",
	})
	if gesture == "walk":
		for _frame in range(14):
			agent.position.z -= 0.025
			await process_frame
	else:
		await create_timer(0.24).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(output_path)
	if error != OK:
		push_error("LOCAL_CHARACTER_PERFORMANCE_PREVIEW_FAIL error=%d" % error)
		quit(1)
		return
	print("LOCAL_CHARACTER_PERFORMANCE_PREVIEW_PASS path=%s" % output_path)
	quit(0)
