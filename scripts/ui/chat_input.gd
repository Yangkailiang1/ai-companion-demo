# chat_input.gd — 聊天输入 UI
extends Control

@onready var line_edit: LineEdit = $Panel/LineEdit
@onready var send_button: Button = $Panel/SendButton
@onready var chat_log: RichTextLabel = $ChatLog

func _ready():
	line_edit.text_submitted.connect(_on_send)
	send_button.pressed.connect(_on_button_press)

	# 监听消息路由
	MessageBus.ui_add_chat_entry.connect(_on_chat_entry)
	MessageBus.ui_show_bubble.connect(_on_show_bubble)


func _on_send(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty(): return
	line_edit.clear()
	MessageBus.route_player_input(text)


func _on_button_press() -> void:
	_on_send(line_edit.text)


func _on_chat_entry(speaker: String, text: String, is_player: bool) -> void:
	var color = "#4a9eff" if is_player else "#ff8f8f"
	chat_log.append_text("[color=%s][%s][/color] %s\n" % [color, speaker, text])


func _on_show_bubble(text: String, emotion: String, duration: float) -> void:
	# Demo: 直接用聊天日志显示气泡效果
	_on_chat_entry("小叶子", text, false)
