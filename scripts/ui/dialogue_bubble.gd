# dialogue_bubble.gd — 世界空间中的对话气泡（浮在角色头上）
extends Sprite3D

@onready var label: Label3D = $BubbleLabel
var timer: Timer
var is_showing: bool = false

func _ready():
	timer = Timer.new()
	add_child(timer)
	timer.timeout.connect(hide_bubble)
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
