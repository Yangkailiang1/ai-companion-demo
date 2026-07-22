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

var display_names = {"main_agent": "咕咕嘎嘎"}
const PLAYER_NAME := "你"
const MAX_CHAT_LINES := 18
const STATE_COLORS := {
	"ready": "#9bd8ff",
	"pending": "#ffe08a",
	"queued": "#ffbd66",
	"thinking": "#ffe08a",
	"online": "#8ee6b0",
	"local": "#c6b5ff",
	"done": "#8ee6b0",
	"error": "#ff8f8f",
}
var _chat_entries: Array[String] = []


func _ready():
	if not line_edit or not send_button:
		push_error("ChatInput: missing LineEdit or SendButton")
		return

	line_edit.text_submitted.connect(_on_send)
	send_button.pressed.connect(_on_button_press)
	MessageBus.ui_add_chat_entry.connect(_on_chat_entry)
	MessageBus.ui_status_changed.connect(_on_status_changed)
	_apply_visual_style()
	line_edit.placeholder_text = "和咕咕嘎嘎说点什么..."
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
	var name = display_names.get(speaker, speaker) if not is_player else PLAYER_NAME
	var color = "#8ecbff" if is_player else "#ffb3c1"
	_chat_entries.append("[color=%s][%s][/color] %s" % [color, name, text])
	while _chat_entries.size() > MAX_CHAT_LINES:
		_chat_entries.pop_front()
	chat_log.clear()
	chat_log.append_text("\n".join(_chat_entries) + "\n")
	_update_chat_panel_presence()


func _on_status_changed(message: String, state: String) -> void:
	if not status_label:
		return
	var color = STATE_COLORS.get(state, "#ffffff")
	status_label.text = "AI 状态：%s" % message
	status_label.modulate = Color(color)


func _apply_visual_style() -> void:
	theme = Theme.new()
	_style_panel($HUD, Color(0.045, 0.06, 0.085, 0.78), Color(0.34, 0.48, 0.62, 0.72))
	_style_panel($ChatPanel, Color(0.035, 0.045, 0.065, 0.38), Color(0.32, 0.48, 0.64, 0.35))
	_style_panel($InputArea, Color(0.035, 0.045, 0.065, 0.86), Color(0.42, 0.62, 0.78, 0.72))
	_style_panel($StatusPanel, Color(0.035, 0.045, 0.065, 0.76), Color(0.32, 0.48, 0.64, 0.56))
	_style_line_edit()
	_style_send_button()
	for bar in [hud_hunger, hud_energy, hud_fun, hud_social]:
		_style_progress_bar(bar)
	if chat_log:
		chat_log.add_theme_color_override("default_color", Color(0.92, 0.95, 1.0, 1.0))
		chat_log.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
		chat_log.add_theme_constant_override("shadow_offset_x", 1)
		chat_log.add_theme_constant_override("shadow_offset_y", 1)
	_update_chat_panel_presence()


func _style_panel(panel: Panel, bg: Color, border: Color) -> void:
	if not panel:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)


func _style_line_edit() -> void:
	if not line_edit:
		return
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.105, 0.135, 0.96)
	normal.border_color = Color(0.46, 0.66, 0.82, 0.8)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(7)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = Color(0.67, 0.83, 1.0, 1.0)
	line_edit.add_theme_stylebox_override("normal", normal)
	line_edit.add_theme_stylebox_override("focus", focus)
	line_edit.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 1.0))
	line_edit.add_theme_color_override("font_placeholder_color", Color(0.62, 0.7, 0.78, 0.82))


func _style_send_button() -> void:
	if not send_button:
		return
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.24, 0.48, 0.68, 0.95)
	normal.border_color = Color(0.62, 0.84, 1.0, 0.75)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(7)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.32, 0.58, 0.78, 1.0)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.18, 0.38, 0.56, 1.0)
	send_button.add_theme_stylebox_override("normal", normal)
	send_button.add_theme_stylebox_override("hover", hover)
	send_button.add_theme_stylebox_override("pressed", pressed)
	send_button.add_theme_color_override("font_color", Color(0.97, 0.99, 1.0, 1.0))


func _style_progress_bar(bar: ProgressBar) -> void:
	if not bar:
		return
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.1, 0.13, 0.9)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.52, 0.72, 0.88, 0.92)
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)


func _update_chat_panel_presence() -> void:
	var chat_panel := $ChatPanel as Panel
	if not chat_panel:
		return
	if _chat_entries.is_empty():
		chat_panel.visible = false
	else:
		chat_panel.visible = true
		_style_panel(chat_panel, Color(0.035, 0.045, 0.065, 0.68), Color(0.42, 0.62, 0.78, 0.62))
		chat_log.modulate = Color(1.0, 1.0, 1.0, 1.0)
