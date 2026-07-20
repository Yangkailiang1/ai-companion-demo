# Spatial Autonomy v0.3

## What changed

The penguin now has four separate runtime layers:

1. **Cognition** — chooses a bounded goal or validated multi-step plan.
2. **Planning** — composes primitive actions instead of requiring one canned clip per behavior.
3. **Navigation** — moves the CharacterBody3D through a real NavigationRegion3D.
4. **Animation** — keeps the existing in-place `walk` clip synchronized with world movement.

“绕着整个房间转一圈” is not an animation clip. It resolves to `PATROL`, expands to a
closed list of nine position targets, and executes each NavigationMesh path in sequence.

## Spatial primitives

- `NAVIGATE`: move to an existing semantic object.
- `NAVIGATE_POSITION`: move to an allowlisted named waypoint.
- `PATROL`: follow a named, closed route for a bounded number of laps.
- `WANDER`: choose a safe point at least one metre from the current position.

Static room bounds, obstacle rectangles, waypoints, routes, and wander points live in
`data/scene_config.json`. Positions are currently LivingRoom-local coordinates; the room
is instantiated at world origin in v0.3.

## Navigation

`room_navigation_region.gd` creates a 0.25 m procedural NavigationMesh grid. Sofa,
coffee table, and plant footprints are expanded for the penguin collision radius and
removed from the walkable mesh. The agent falls back to direct movement only if the
NavigationServer map has not completed both runtime synchronization iterations.

Movement has a 20 second timeout, 2.5 second stuck detector, cancellation, smooth yaw,
and explicit success/failure completion. A newer decision cancels the previous physical
queue. Autonomous idle/simulation triggers never interrupt an active player task.

## Structured LLM plans

The optional `plan` array accepts at most six steps. Allowed step names are:

`navigate_object`, `navigate_waypoint`, `patrol`, `wander`, `look_at`, `interact`, `wait`.

Object IDs, verbs, waypoint names, route names, lap counts, and wait durations are
validated. Coordinates and unknown actions are rejected; the runtime falls back to the
existing GOAP goal path.

## Chinese local intents

- “绕房间走一圈 / 转一圈 / 巡逻” → `patrol_room`
- “随便走走 / 在房间逛逛 / 走一走” → `wander_room`

## Tests

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/headless_check.gd

/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/gesture_pipeline_check.gd

/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/spatial_autonomy_check.gd
```

The spatial test verifies NavigationMesh synchronization and reachability, route closure,
safe wander points, plan rejection, Chinese intent resolution, visible world displacement,
walk/idle animation state, and termination of a complete lap.

## Still predefined vs dynamic

Predefined: seven body animation clips, the primitive action vocabulary, room obstacle
footprints, and named safe routes/waypoints.

Dynamic: the selected goal, validated ordering of plan steps, generated navigation path,
turning direction, exact frame-by-frame world position, idle wander choice, cancellation,
and replanning.

Text-to-motion remains a later optional expression layer. It is not required for spatial
autonomy and should not control collision-critical navigation or object contact.

## Known limitations

- Furniture collision and navigation footprints are greybox approximations.
- There is no player avatar yet, so `FOLLOW` is not exposed.
- Object hand contact still needs IK; pick-up/put-down are timing placeholders.
- Runtime NavigationMesh assumes the current single-level living room.
- Long-term schedules, curiosity and reflection remain future cognition work.
