# chat_input.gd — 聊天输入 UI + HUD
# Demo 层：提供玩家输入、聊天显示、状态 HUD

extends Control

@onready var line_edit: LineEdit = $InputArea/LineEdit
@onready var send_button: Button = $InputArea/SendButton
@onready var chat_log: RichTextLabel = $ChatPanel/ChatLog
@onready var hud_time: Label = $HUD/HUDLayout/TimeDisplay
@onready var hud_hunger: ProgressBar = $HUD/HUDLayout/HungerRow/HungerBar
@onready var hud_energy: ProgressBar = $HUD/HUDLayout/EnergyRow/EnergyBar
@onready var hud_fun: ProgressBar = $HUD/HUDLayout/FunRow/FunBar
@onready var hud_social: ProgressBar = $HUD/HUDLayout/SocialRow/SocialBar
@onready var status_label: Label = $StatusPanel/StatusLabel

var display_names = {"main_agent": "小叶子"}


func _ready():
	if not line_edit or not send_button:
		push_error("ChatInput: missing LineEdit or SendButton")
		return

	line_edit.text_submitted.connect(_on_send)
	send_button.pressed.connect(_on_button_press)
	MessageBus.ui_add_chat_entry.connect(_on_chat_entry)
	MessageBus.ui_status_changed.connect(_on_status_changed)
	line_edit.placeholder_text = "输入你想说的话..."
	line_edit.grab_focus.call_deferred()
	var mode = "在线 AI：%s/%s" % [CognitiveCycle.llm_provider, CognitiveCycle.llm_model]
	if CognitiveCycle.llm_api_url.is_empty() or CognitiveCycle.llm_api_key.is_empty():
		mode = "本地规则模式（未连接 AI）"
	_on_status_changed(mode, "ready")


func _process(_delta: float) -> void:
	# 持续更新 HUD（跳过如果节点未就绪）
	if not hud_time or not hud_hunger or not hud_energy or not hud_fun or not hud_social:
		return

	var sim = WorldSimulator.get_state_snapshot()
	var needs = sim["needs"]

	hud_time.text = "第%d天 %s (%.0f:00)" % [sim["day"], sim["time_of_day"], sim["game_time"]]
	hud_hunger.value = needs["hunger"]
	hud_energy.value = needs["energy"]
	hud_fun.value = needs["fun"]
	hud_social.value = needs["social"]


func _on_send(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty(): return
	line_edit.clear()
	MessageBus.route_player_input(text)


func _on_button_press() -> void:
	_on_send(line_edit.text)


func _on_chat_entry(speaker: String, text: String, is_player: bool) -> void:
	if text.is_empty() or not chat_log:
		return
	var name = display_names.get(speaker, speaker) if not is_player else speaker
	var color = "#4a9eff" if is_player else "#ff8f8f"
	chat_log.append_text("[color=%s][%s][/color] %s\n" % [color, name, text])


func _on_status_changed(message: String, state: String) -> void:
	if not status_label:
		return
	var color = {
		"ready": "#a9d5ff",
		"pending": "#ffe08a",
		"queued": "#ffbd66",
		"thinking": "#ffe08a",
		"online": "#8ee6b0",
		"local": "#c6b5ff",
		"done": "#8ee6b0",
		"error": "#ff8f8f",
	}.get(state, "#ffffff")
	status_label.text = "AI 状态：%s" % message
	status_label.modulate = Color(color)
