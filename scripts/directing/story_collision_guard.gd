# Roadmap: D2.1, C4.1, C4.4
# Responsibility: Manage temporary character collision exceptions for staged
# blocking and restore only physically separated pairs; does not move agents.
# Collaborators: StoryDirector, AgentBase, NavigationAgent3D
# Tests: scripts/debug/story_director_check.gd

extends RefCounted

const RESTORE_MARGIN := 0.12


## [D2.1][C4.1] Enables cast passage through all residents during blocking.
func enable(cast_nodes: Dictionary, cast_ids: Array, all_agents: Array) -> void:
	for actor_id in cast_ids:
		var actor = cast_nodes.get(actor_id)
		if not actor is CollisionObject3D:
			continue
		for other in all_agents:
			if other == actor or not other is CollisionObject3D:
				continue
			actor.add_collision_exception_with(other)
			other.add_collision_exception_with(actor)


## [D2.1][C4.4] Restores separated pairs but retains exceptions for overlaps,
## preventing the physics solver from ejecting actors from final stage marks.
func restore_safely(
	cast_nodes: Dictionary,
	cast_ids: Array,
	all_agents: Array,
) -> int:
	var retained := 0
	for actor_id in cast_ids:
		var actor = cast_nodes.get(actor_id)
		if not actor is CollisionObject3D:
			continue
		for other in all_agents:
			if other == actor or not other is CollisionObject3D:
				continue
			if _is_safely_separated(actor, other):
				actor.remove_collision_exception_with(other)
				other.remove_collision_exception_with(actor)
			else:
				retained += 1
	return retained


## [C4.1] Compares horizontal spacing against both capsule radii plus margin.
func _is_safely_separated(first: CollisionObject3D, second: CollisionObject3D) -> bool:
	var first_position := first.global_position
	var second_position := second.global_position
	first_position.y = 0.0
	second_position.y = 0.0
	var clearance := _collision_radius(first) + _collision_radius(second) + RESTORE_MARGIN
	return first_position.distance_to(second_position) > clearance


## [C4.1] Reads the active capsule radius with a conservative fallback.
func _collision_radius(actor: CollisionObject3D) -> float:
	var shape_node := actor.get_node_or_null("AgentCollision") as CollisionShape3D
	if shape_node != null and shape_node.shape is CapsuleShape3D:
		return (shape_node.shape as CapsuleShape3D).radius
	return 0.38
