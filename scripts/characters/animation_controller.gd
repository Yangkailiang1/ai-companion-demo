# animation_controller.gd — 简易动画控制器
# Demo 阶段用程序化移动 + 颜色变化替代骨骼动画
# 后续版本替换为 AnimationTree + 骨骼动画

extends Node3D

# mesh_instance 在场景中通过 inspector 设置，指向子 MeshInstance3D
# 如果未设置，_ready 中自动从第一个子 MeshInstance3D 获取
@export var mesh_instance: MeshInstance3D
@export var default_color: Color = Color(0.4, 0.7, 1.0)

# 动画参数
var bob_height: float = 0.05
var bob_speed: float = 2.0
var bob_offset: float = 0.0
var is_active: bool = true


func _ready():
	# 如果未在 inspector 设置，尝试从子节点获取
	if not mesh_instance:
		for child in get_children():
			if child is MeshInstance3D:
				mesh_instance = child
				break

	if mesh_instance:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = default_color
		mesh_instance.material_override = mat


func _process(delta: float) -> void:
	if not is_active or not mesh_instance:
		return

	# 简单的上下浮动动画（待机时）
	bob_offset += delta * bob_speed
	var y_offset = sin(bob_offset) * bob_height
	mesh_instance.position.y = y_offset


func set_emotion(emotion: String) -> void:
	if not mesh_instance or not mesh_instance.material_override:
		return
	var mat = mesh_instance.material_override as StandardMaterial3D
	match emotion:
		"happy":   mat.albedo_color = Color(0.3, 0.9, 0.4)
		"sad":     mat.albedo_color = Color(0.4, 0.5, 0.9)
		"angry":   mat.albedo_color = Color(0.9, 0.3, 0.2)
		"neutral": mat.albedo_color = default_color
		_:         mat.albedo_color = default_color
