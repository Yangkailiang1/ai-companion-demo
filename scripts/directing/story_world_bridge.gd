# Roadmap: D2, T2.1, S3.2
# Responsibility: Resolve story waypoints, registered cast and semantic object
# interactions; does not manage story phases, timing, camera or character cues.
# Collaborators: StoryDirector, SemanticWorld, CharacterAdapterRegistry
# Tests: scripts/debug/story_director_check.gd

extends RefCounted


## [D2][S3.2] Executes one validated semantic interaction and returns a reason.
func perform_interaction(actor_id: String, interaction: Dictionary) -> Dictionary:
	var object_id := String(interaction.get("object", ""))
	var verb := String(interaction.get("verb", ""))
	var root := _root()
	var semantic := root.get_node_or_null("SemanticWorld") if root != null else null
	var object = semantic.get_object(object_id) if semantic != null else null
	if object == null or not is_instance_valid(object.godot_node):
		return {"ok": false, "reason": "交互物体不可用: %s" % object_id}
	if not object.godot_node.has_method("perform_interaction"):
		return {"ok": false, "reason": "交互物体没有处理器: %s" % object_id}
	var result: Dictionary = object.godot_node.perform_interaction(verb, actor_id)
	if not bool(result.get("handled", false)):
		return {
			"ok": false,
			"reason": "交互被拒绝: %s.%s" % [object_id, verb],
		}
	return {"ok": true, "reason": ""}


## [D1][T2.1] Resolves one validated waypoint/object target to world position.
func resolve_move_target(move_to: Dictionary) -> Vector3:
	if move_to.has("waypoint"):
		var navigation := RoomNavigation.new()
		var waypoint := String(move_to["waypoint"])
		return (
			navigation.get_waypoint(waypoint)
			if navigation.has_waypoint(waypoint) else Vector3.INF
		)
	if move_to.has("object"):
		var root := _root()
		var semantic := root.get_node_or_null("SemanticWorld") if root != null else null
		var object = semantic.get_object(String(move_to["object"])) if semantic != null else null
		return object.interaction_point if object != null else Vector3.INF
	return Vector3.INF


## [D1][C6.2] Returns the live adapter registry cast with a public fallback.
func get_registry_cast() -> Array[String]:
	var root := _root()
	var registry := (
		root.get_node_or_null("CharacterAdapterRegistry")
		if root != null else null
	)
	return (
		registry.get_registered_agent_ids()
		if registry != null else ["main_agent", "jue_agent"]
	)


## [T4.2] Returns the SceneTree root without retaining scene ownership.
func _root() -> Window:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root if tree != null else null
