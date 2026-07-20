class_name PlanValidator

extends RefCounted

const MAX_STEPS := 6
const MAX_WAIT_SECONDS := 10.0
const ALLOWED_ACTIONS := ["navigate_object", "navigate_waypoint", "patrol", "wander", "look_at", "interact", "wait"]


func compile(plan: Variant) -> Array:
	if not plan is Array or plan.is_empty() or plan.size() > MAX_STEPS:
		return []
	var navigation := RoomNavigation.new()
	var semantic_world := _get_semantic_world()
	if semantic_world == null:
		return []
	var compiled: Array = []
	for raw_step in plan:
		if not raw_step is Dictionary:
			return []
		var action_name := String(raw_step.get("action", "")).to_lower()
		if action_name not in ALLOWED_ACTIONS:
			return []
		match action_name:
			"navigate_object":
				var object_id := String(raw_step.get("target", ""))
				if semantic_world.get_object(object_id) == null:
					return []
				compiled.append(_pa(AffordanceTypes.Primitive.NAVIGATE, {"target": object_id}))
			"navigate_waypoint":
				var waypoint := String(raw_step.get("waypoint", ""))
				if not navigation.has_waypoint(waypoint):
					return []
				compiled.append(_pa(AffordanceTypes.Primitive.NAVIGATE_POSITION, {"waypoint": waypoint}))
			"patrol":
				var route := String(raw_step.get("route", "room_perimeter"))
				if navigation.get_route(route).size() < 2:
					return []
				compiled.append(_pa(AffordanceTypes.Primitive.PATROL, {"route": route, "laps": clampi(int(raw_step.get("laps", 1)), 1, 2)}))
			"wander":
				compiled.append(_pa(AffordanceTypes.Primitive.WANDER, {}))
			"look_at":
				var target := String(raw_step.get("target", ""))
				if semantic_world.get_object(target) == null:
					return []
				compiled.append(_pa(AffordanceTypes.Primitive.LOOK_AT, {"target": target}))
			"interact":
				var object_id := String(raw_step.get("target", ""))
				var verb := String(raw_step.get("verb", ""))
				if semantic_world.get_object(object_id) == null or not semantic_world.can_interact(object_id, verb):
					return []
				compiled.append(_pa(AffordanceTypes.Primitive.INTERACT, {"object": object_id, "verb": verb}))
			"wait":
				var duration := clampf(float(raw_step.get("duration", 1.0)), 0.1, MAX_WAIT_SECONDS)
				compiled.append(_pa(AffordanceTypes.Primitive.IDLE, {"duration": duration}))
	return compiled


func _pa(type: AffordanceTypes.Primitive, params: Dictionary) -> AffordanceTypes.PrimitiveAction:
	return AffordanceTypes.PrimitiveAction.new(type, params)


func _get_semantic_world() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("SemanticWorld") if tree else null
