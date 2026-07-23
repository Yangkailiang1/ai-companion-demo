# dialogue_bubble.gd — 世界空间中的对话气泡（浮在角色头上）
extends Sprite3D

@onready var label: Label3D = $BubbleLabel
@export var agent_id: String = ""
var timer: Timer
var is_showing: bool = false

func _ready():
	if agent_id.is_empty():
		agent_id = _infer_agent_id()
	timer = Timer.new()
	add_child(timer)
	timer.timeout.connect(hide_bubble)
	if MessageBus.has_signal("agent_show_bubble"):
		MessageBus.agent_show_bubble.connect(_on_agent_show_bubble)


func _infer_agent_id() -> String:
	var node := get_parent()
	while node:
		if "agent_name" in node:
			return String(node.agent_name)
		node = node.get_parent()
	return "main_agent"


func _on_agent_show_bubble(target_agent_id: String, text: String, emotion: String, duration: float) -> void:
	if target_agent_id != agent_id:
		return
	show_bubble(text, emotion, duration)


func show_bubble(text: String, emotion: String, duration: float) -> void:
	if label:
		label.text = text
	is_showing = true
	visible = true
	timer.start(duration)


func hide_bubble() -> void:
	visible = false
	is_showing = false
