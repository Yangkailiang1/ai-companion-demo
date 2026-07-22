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
@onready var camera_hint: Label = $CameraHint

var display_names = {"main_agent": "咕咕嘎嘎"}
const PLAYER_NAME := "你"
const MAX_CHAT_LINES := 18
const STATE_COLORS := {
	"ready": "#7f5b36",
	"pending": "#a06b2f",
	"queued": "#b75f38",
	"thinking": "#a06b2f",
	"online": "#4f7a4d",
	"local": "#7b5a8f",
	"done": "#4f7a4d",
	"error": "#a9483e",
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
	var color = "#7a4b2b" if is_player else "#a65b42"
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
	_style_panel($HUD, Color(0.98, 0.86, 0.66, 0.76), Color(0.69, 0.43, 0.22, 0.48), 14)
	_style_panel($ChatPanel, Color(0.98, 0.88, 0.7, 0.56), Color(0.73, 0.46, 0.25, 0.38), 16)
	_style_panel($InputArea, Color(0.98, 0.88, 0.72, 0.92), Color(0.78, 0.5, 0.27, 0.64), 18)
	_style_panel($StatusPanel, Color(0.98, 0.88, 0.7, 0.82), Color(0.73, 0.46, 0.25, 0.52), 14)
	_style_line_edit()
	_style_send_button()
	for bar in [hud_hunger, hud_energy, hud_fun, hud_social]:
		_style_progress_bar(bar)
	if chat_log:
		chat_log.add_theme_color_override("default_color", Color(0.22, 0.14, 0.09, 1.0))
		chat_log.add_theme_color_override("font_shadow_color", Color(1.0, 0.92, 0.76, 0.42))
		chat_log.add_theme_constant_override("shadow_offset_x", 1)
		chat_log.add_theme_constant_override("shadow_offset_y", 1)
	_style_labels()
	_update_chat_panel_presence()


func _style_panel(panel: Panel, bg: Color, border: Color, radius: int = 10) -> void:
	if not panel:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.22, 0.12, 0.04, 0.22)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 3)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)


func _style_line_edit() -> void:
	if not line_edit:
		return
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1.0, 0.95, 0.84, 0.96)
	normal.border_color = Color(0.76, 0.48, 0.24, 0.72)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(12)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 7
	normal.content_margin_bottom = 7
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = Color(0.96, 0.62, 0.28, 1.0)
	line_edit.add_theme_stylebox_override("normal", normal)
	line_edit.add_theme_stylebox_override("focus", focus)
	line_edit.add_theme_color_override("font_color", Color(0.22, 0.13, 0.08, 1.0))
	line_edit.add_theme_color_override("font_placeholder_color", Color(0.48, 0.33, 0.22, 0.72))


func _style_send_button() -> void:
	if not send_button:
		return
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.82, 0.47, 0.22, 0.96)
	normal.border_color = Color(1.0, 0.72, 0.38, 0.82)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(12)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.93, 0.56, 0.25, 1.0)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.68, 0.36, 0.18, 1.0)
	send_button.add_theme_stylebox_override("normal", normal)
	send_button.add_theme_stylebox_override("hover", hover)
	send_button.add_theme_stylebox_override("pressed", pressed)
	send_button.add_theme_color_override("font_color", Color(1.0, 0.96, 0.86, 1.0))


func _style_progress_bar(bar: ProgressBar) -> void:
	if not bar:
		return
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.68, 0.48, 0.29, 0.22)
	bg.set_corner_radius_all(6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.87, 0.49, 0.25, 0.92)
	fill.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)


func _style_labels() -> void:
	for label in [
		$HUD/HUDLayout/AgentName,
		hud_time,
		$HUD/HUDLayout/HungerRow/HungerLabel,
		$HUD/HUDLayout/EnergyRow/EnergyLabel,
		$HUD/HUDLayout/FunRow/FunLabel,
		$HUD/HUDLayout/SocialRow/SocialLabel,
		status_label,
		camera_hint,
	]:
		if label:
			label.add_theme_color_override("font_color", Color(0.25, 0.15, 0.09, 1.0))
			label.add_theme_color_override("font_shadow_color", Color(1.0, 0.92, 0.78, 0.35))
			label.add_theme_constant_override("shadow_offset_x", 1)
			label.add_theme_constant_override("shadow_offset_y", 1)
	if camera_hint:
		camera_hint.modulate = Color(0.36, 0.23, 0.15, 0.72)


func _update_chat_panel_presence() -> void:
	var chat_panel := $ChatPanel as Panel
	if not chat_panel:
		return
	if _chat_entries.is_empty():
		chat_panel.visible = false
	else:
		chat_panel.visible = true
		_style_panel(chat_panel, Color(0.98, 0.88, 0.7, 0.78), Color(0.73, 0.46, 0.25, 0.54), 16)
		chat_log.modulate = Color(1.0, 1.0, 1.0, 1.0)
