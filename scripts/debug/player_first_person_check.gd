# Verifies: P2.1, P2.3, P2.4
# Covers: observer orbit -> first-person collision movement -> chat focus lock
# -> mode return -> cross-location player entry.

extends SceneTree

const KITCHEN_PLAYER_ENTRY := Vector3(0.0, 0.9, 2.15)
const KITCHEN_AGENT_SPAWN := Vector3(-0.65, 0.0, 1.8)

var _failed := false


## [P2.3] 延迟执行，等待主场景 Autoload 初始化。
func _init() -> void:
	call_deferred("_run")


## [P2.1][P2.3][P2.4] 编排玩家控制纵向合同验收。
func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	root.get_node("AutonomousBehaviorSystem").set_scheduler_enabled(false)
	var loader := scene.get_node("WorldRoot") as WorldLocationLoader
	_assert(loader.switch_location("parametric") == "parametric", "parametric init")
	await _settle()
	var player := scene.get_node("WorldRoot/PlayerBody") as CharacterBody3D
	var camera := scene.get_node("WorldRoot/Camera3D") as Camera3D
	_verify_body_contract(player)
	await _verify_modes_and_movement(scene, player, camera)
	await _verify_travel(loader, player)
	scene.free()
	await process_frame
	if not _failed:
		print("PLAYER_FIRST_PERSON_PASS modes=2 collision=true travel=true mouse_capture=true")
	quit(1 if _failed else 0)


## [P2.2][P2.3] 验证持久玩家只有碰撞控制底座，没有临时胶囊视觉。
func _verify_body_contract(player: CharacterBody3D) -> void:
	_assert(player != null, "PlayerBody missing")
	if player == null:
		return
	var collision := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	_assert(collision != null and collision.shape is CapsuleShape3D, "capsule collision missing")
	_assert(
		player.find_children("*", "MeshInstance3D", true, false).is_empty(),
		"temporary player mesh must not be visible",
	)


## [P2.1][P2.3][P2.4] 验证模式、碰撞移动、文本焦点和提示联动。
func _verify_modes_and_movement(
	scene: Node,
	player: CharacterBody3D,
	camera: Camera3D,
) -> void:
	_assert(camera.get_view_mode() == "observer", "observer not default")
	_assert(not player.is_control_enabled(), "observer movement enabled")
	_assert(not camera.set_view_mode("bad_mode"), "invalid mode accepted")
	root.gui_release_focus()
	var orbit_before := camera.global_position
	_drag_camera(camera, Vector2(120.0, -20.0))
	_assert(camera.global_position.distance_to(orbit_before) > 0.2, "observer orbit failed")
	_assert(camera.set_view_mode("first_person"), "first-person switch failed")
	await process_frame
	_assert(player.is_control_enabled(), "first-person movement disabled")
	_assert(camera.is_pointer_captured(), "first-person did not capture mouse")
	_assert(
		camera.global_position.distance_to(player.get_eye_global_position()) < 0.02,
		"camera not at eye",
	)
	await create_timer(0.12).timeout
	var look_before := camera.global_rotation
	_move_mouse(camera, Vector2(90.0, -25.0))
	_assert(camera.global_rotation.distance_to(look_before) > 0.05, "free mouse look failed")
	camera._input(_key_event(KEY_ESCAPE, true))
	_assert(not camera.is_pointer_captured(), "Esc did not release mouse")
	var released_rotation := camera.global_rotation
	_move_mouse(camera, Vector2(120.0, 20.0))
	_assert(
		camera.global_rotation.distance_to(released_rotation) < 0.01,
		"released mouse still changed view",
	)
	_right_click(camera)
	_assert(camera.is_pointer_captured(), "right click did not recapture mouse")
	var move_before := player.global_position
	_send_key(KEY_W, true)
	await _physics_frames(75)
	_send_key(KEY_W, false)
	_assert(player.global_position.distance_to(move_before) > 0.3, "W did not move player")
	_assert(absf(player.global_position.x) < 4.0 and absf(player.global_position.z) < 4.0,
		"collision allowed player outside room")
	await _verify_focus_lock(scene, player, camera)
	var hint := scene.find_child("CameraHint", true, false) as Label
	_assert(hint != null and "第一人称" in hint.text, "first-person hint missing")
	root.gui_release_focus()
	camera._input(_key_event(KEY_V, true))
	await process_frame
	_assert(camera.get_view_mode() == "observer", "V did not return observer")
	_assert(not player.is_control_enabled(), "observer did not disable movement")
	_assert(hint != null and "观察" in hint.text, "observer hint missing")


## [P2.3][S1] 验证聊天聚焦时移动、拖拽和 V 模式切换均被冻结。
func _verify_focus_lock(scene: Node, player: CharacterBody3D, camera: Camera3D) -> void:
	var line_edit := scene.find_child("LineEdit", true, false) as LineEdit
	_assert(line_edit != null, "LineEdit missing")
	if line_edit == null:
		return
	line_edit.grab_focus()
	await process_frame
	var body_before := player.global_position
	var rotation_before := camera.global_rotation
	_send_key(KEY_W, true)
	_drag_camera(camera, Vector2(180.0, 30.0))
	camera._input(_key_event(KEY_V, true))
	await _physics_frames(12)
	_send_key(KEY_W, false)
	_assert(player.global_position.distance_to(body_before) < 0.03, "moved while typing")
	_assert(camera.global_rotation.distance_to(rotation_before) < 0.01, "look changed while typing")
	_assert(camera.get_view_mode() == "first_person", "V toggled while typing")
	_assert(not camera.is_pointer_captured(), "text focus did not release mouse")


## [P2.3][S2.2] 验证玩家入口与 AI Cast 出生策略解耦。
func _verify_travel(loader: WorldLocationLoader, player: CharacterBody3D) -> void:
	_assert(loader.travel_via("to_kitchen"), "living to kitchen failed")
	await _settle()
	_assert(player.global_position.distance_to(KITCHEN_PLAYER_ENTRY) < 0.06, "player entry wrong")
	var agent := loader.get_active_location().get_node_or_null("Agent") as Node3D
	_assert(agent != null, "kitchen Agent missing")
	if agent != null:
		_assert(agent.position.distance_to(KITCHEN_AGENT_SPAWN) < 0.06, "AI used player entry")
	_assert(loader.travel_via("to_living"), "kitchen return failed")
	await _settle()
	var camera := loader.get_node("Camera3D")
	_assert(camera.set_view_mode("first_person"), "first-person re-entry failed")


## [P2.1][P2.3] 合成一次右键拖拽。
func _drag_camera(camera: Camera3D, relative: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.position = Vector2(640.0, 360.0)
	camera._input(press)
	var drag := InputEventMouseMotion.new()
	drag.relative = relative
	drag.position = press.position + relative
	camera._input(drag)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	release.position = drag.position
	camera._input(release)


## [P2.3] 合成无需按键的捕获鼠标移动。
func _move_mouse(camera: Camera3D, relative: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.relative = relative
	motion.position = Vector2(640.0, 360.0)
	camera._input(motion)


## [P2.3] 在第一人称释放状态下合成右键重捕获。
func _right_click(camera: Camera3D) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	event.position = Vector2(640.0, 360.0)
	camera._input(event)


## [P2.3] 向 Input 单例发送物理键状态。
func _send_key(keycode: Key, pressed: bool) -> void:
	Input.parse_input_event(_key_event(keycode, pressed))


## [P2.3][P2.4] 构造物理键事件；纯函数。
func _key_event(keycode: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	return event


## [P2.2] 等待指定物理帧数。
func _physics_frames(count: int) -> void:
	for _frame in range(count):
		await physics_frame


## [P2.3][S2.2] 等待房间构建和物理落地。
func _settle() -> void:
	for _frame in range(8):
		await physics_frame
		await process_frame


## [P2.3] 累积失败诊断。
func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("PLAYER_FIRST_PERSON_FAIL: " + message)
