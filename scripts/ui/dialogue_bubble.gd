# dialogue_bubble.gd — 世界空间中的对话气泡（浮在角色头上）
extends Sprite3D

@onready var label: Label3D = $Label3D
@onready var timer: Timer = $Timer

var is_showing: bool = false

func _ready():
	if not timer:
		timer = Timer.new()
		add_child(timer)
	timer.timeout.connect(hide_bubble)

	# 监听气泡信号
	MessageBus.ui_show_bubble.connect(show_bubble)


func show_bubble(text: String, emotion: String, duration: float) -> void:
	if label:
		label.text = text
	is_showing = true
	visible = true
	timer.start(duration)


func hide_bubble() -> void:
	visible = false
	is_showing = false
