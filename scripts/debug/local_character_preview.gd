# Roadmap: C6.1, C8.1, O4
# Responsibility: Render a neutral close-up of an optional local-only character
# for visual QA; never modifies or redistributes the source model.
# Tests: Run with Godot --path . --script <this file>.

extends SceneTree

const DEFAULT_MODEL_PATH := "res://assets/local_characters/castorice/castorice.glb"
const DEFAULT_OUTPUT_PATH := "/private/tmp/castorice_preview.png"


func _init() -> void:
	call_deferred("_run")


## [C6.1][C8.1] 构建临时灯光与相机，输出本地角色近景。
func _run() -> void:
	root.size = Vector2i(900, 900)
	var args := OS.get_cmdline_user_args()
	var model_path := String(args[0]) if args.size() > 0 else DEFAULT_MODEL_PATH
	var output_path := String(args[1]) if args.size() > 1 else DEFAULT_OUTPUT_PATH
	if not ResourceLoader.exists(model_path):
		print("LOCAL_CHARACTER_PREVIEW_SKIP path=%s" % model_path)
		quit(0)
		return
	var stage := Node3D.new()
	root.add_child(stage)
	var model := (load(model_path) as PackedScene).instantiate() as Node3D
	stage.add_child(model)
	await process_frame
	var bounds := _find_bounds(model)
	_add_environment(stage)
	_add_camera(stage, bounds)
	await create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(output_path)
	if error != OK:
		push_error("LOCAL_CHARACTER_PREVIEW_FAIL error=%d" % error)
		quit(1)
		return
	print("LOCAL_CHARACTER_PREVIEW_PASS path=%s bounds=%s" % [output_path, bounds])
	quit(0)


## [C8.1] 以全部 MeshInstance3D 的世界包围盒计算构图范围。
func _find_bounds(root_node: Node3D) -> AABB:
	var result := AABB()
	var has_bounds := false
	for node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if not mesh_node.mesh:
			continue
		var world_box := mesh_node.global_transform * mesh_node.get_aabb()
		result = result.merge(world_box) if has_bounds else world_box
		has_bounds = true
	return result


## [C8.1] 添加暖色世界环境和双灯布光。
func _add_environment(stage: Node3D) -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#d9c5b5")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#fff0dc")
	environment.ambient_light_energy = 0.62
	world.environment = environment
	stage.add_child(world)
	for setup in [[Vector3(-3, 5, 4), 1.3], [Vector3(3, 2, 2), 0.55]]:
		var light := OmniLight3D.new()
		light.position = setup[0]
		light.omni_range = 12.0
		light.light_energy = setup[1]
		stage.add_child(light)


## [C8.1] 根据模型高度放置透视相机并朝向包围盒中心。
func _add_camera(stage: Node3D, bounds: AABB) -> void:
	var center := bounds.get_center()
	var extent := maxf(bounds.size.y, maxf(bounds.size.x, bounds.size.z))
	var camera := Camera3D.new()
	camera.position = center + Vector3(0, extent * 0.08, extent * 1.8)
	stage.add_child(camera)
	camera.look_at(center + Vector3(0, extent * 0.04, 0), Vector3.UP)
	camera.fov = 38.0
