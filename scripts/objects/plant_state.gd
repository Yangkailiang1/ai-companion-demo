class_name PlantState
extends Node

@export_range(0.0, 100.0, 1.0) var moisture := 28.0
@export_range(0.0, 100.0, 1.0) var health := 82.0
@export_range(0, 3, 1) var growth_stage := 1
@export var moisture_decay_per_hour := 4.0
var healthy_hours := 0

var _model: Node3D
var _status_label: Label3D
var _base_scale := Vector3.ONE
var _base_rotation := Vector3.ZERO


func _ready() -> void:
	_model = get_parent().get_node_or_null("PottedPlantModel")
	_status_label = get_parent().get_node_or_null("PlantStatusLabel")
	if _model:
		_base_scale = _model.scale
		_base_rotation = _model.rotation
	WorldSimulator.game_hour_advanced.connect(_on_game_hour_advanced)
	MessageBus.world_state_changed.connect(_on_world_state_changed)
	_import_semantic_properties()
	_sync_state()


func perform_interaction(verb: String, _actor_id: String = "") -> Dictionary:
	match verb:
		"water":
			moisture = clampf(moisture + 48.0, 0.0, 100.0)
			health = clampf(health + 5.0, 0.0, 100.0)
		"prune":
			if health >= 45.0:
				health = clampf(health + 3.0, 0.0, 100.0)
			else:
				return {"handled": true, "success": false, "reason": "plant_too_weak"}
		_:
			return {"handled": false}
	_sync_state()
	return {"handled": true, "success": true, "state": get_state_name()}


func advance_hours(hours: int) -> void:
	for _index in range(maxi(hours, 0)):
		moisture = clampf(moisture - moisture_decay_per_hour, 0.0, 100.0)
		if moisture < 20.0:
			health = clampf(health - 5.0, 0.0, 100.0)
		elif moisture >= 35.0 and moisture <= 85.0:
			health = clampf(health + 1.0, 0.0, 100.0)
		if health >= 85.0 and moisture >= 40.0:
			healthy_hours += 1
			if healthy_hours >= 24:
				growth_stage = mini(growth_stage + 1, 3)
				healthy_hours = 0
		else:
			healthy_hours = maxi(healthy_hours - 1, 0)
	_sync_state()


func get_save_state() -> Dictionary:
	return {
		"moisture": moisture,
		"health": health,
		"growth_stage": growth_stage,
		"healthy_hours": healthy_hours,
	}


func get_state_name() -> String:
	if health <= 20.0:
		return "枯萎"
	if moisture <= 20.0:
		return "严重缺水"
	if moisture <= 35.0:
		return "需要浇水"
	if growth_stage >= 3:
		return "茁壮成长"
	return "状态良好"


func _on_game_hour_advanced(_day: int, _hour: float) -> void:
	advance_hours(1)


func _on_world_state_changed(change_type: String, _data: Dictionary) -> void:
	if change_type == "save_loaded":
		_import_semantic_properties()
		_refresh_visual()


func _import_semantic_properties() -> void:
	var object = SemanticWorld.get_object("plant")
	if not object:
		return
	var properties: Dictionary = object.properties
	moisture = clampf(float(properties.get("moisture", moisture)), 0.0, 100.0)
	health = clampf(float(properties.get("health", health)), 0.0, 100.0)
	growth_stage = clampi(int(properties.get("growth_stage", growth_stage)), 0, 3)
	healthy_hours = maxi(int(properties.get("healthy_hours", healthy_hours)), 0)


func _sync_state() -> void:
	SemanticWorld.update_object_properties("plant", get_save_state(), get_state_name())
	_refresh_visual()


func _refresh_visual() -> void:
	if _model:
		var health_factor := lerpf(0.72, 1.0, health / 100.0)
		var growth_factor := 0.82 + float(growth_stage) * 0.09
		_model.scale = _base_scale * Vector3(health_factor, health_factor * growth_factor, health_factor)
		_model.rotation = _base_rotation + Vector3(0.0, 0.0, deg_to_rad(10.0 if health < 35.0 else 0.0))
	if _status_label:
		_status_label.text = "💧%s" % get_state_name()
		_status_label.visible = moisture <= 35.0 or health <= 35.0
