# v0.3 Spatial Autonomy — implementation task

You are implementing the bottom layer. The primary agent will review, run Godot,
repair issues, and perform visual acceptance. Work only inside this repository.
Do not read or modify `data/.env` or `data/llm_config.json`. Do not use network.
Preserve all current penguin/gesture/UI behavior.

## Outcome

The penguin must be able to move around the room, patrol one lap, wander on idle,
and execute multi-step structured plans. This is spatial autonomy, not text-to-motion.

## Required implementation

1. Extend `AffordanceTypes.Primitive` with composable spatial primitives:
   - `NAVIGATE_POSITION`
   - `PATROL`
   - `WANDER`
   - reserve or implement `FOLLOW` only if it can be tested without a player avatar.

2. Add a room navigation specification, preferably in `data/scene_config.json`:
   - walkable bounds
   - named waypoints
   - a perimeter patrol route that avoids sofa/table/TV/plant
   - safe wander points
   Keep positions inside the visible 8m x 8m room.

3. Add a navigation/world helper (separate script, no cognitive dependencies) that:
   - loads/validates named waypoints and routes
   - provides patrol and random wander destinations
   - rejects/clamps unsafe/out-of-room positions
   - is deterministic in tests

4. Upgrade `AgentBase` movement:
   - travel to arbitrary Vector3 positions
   - play walk while moving and idle on arrival
   - face velocity smoothly enough for the chibi model
   - timeout/stuck detection, cancellation, and a clear movement result signal
   - preserve direct fallback, but add a real `NavigationRegion3D`/NavigationMesh if
     reliable in Godot 4.6.1. If baked NavMesh cannot be serialized safely, implement
     collision-aware waypoint routing and document that limitation honestly.
   - do not allow concurrent ActionExecutors to fight over the same agent; new player
     commands should supersede or queue according to a documented policy.

5. Upgrade `ActionExecutor`:
   - execute NAVIGATE_POSITION, PATROL, WANDER
   - patrol must visit multiple points sequentially, not teleport or play a canned clip
   - every await must be cancellation-safe if its agent/action is freed
   - report completion/failure without hanging forever.

6. Upgrade cognitive/planning behavior:
   - local Chinese intents: “绕房间走一圈/转一圈/巡逻” -> patrol_room
   - “随便走走/在房间逛逛” -> wander_room
   - explicit player spatial intents override unrelated LLM output just like TV intent
   - LLM schema may return a bounded `plan` array of structured steps; validate strictly
   - only allow known action names, existing object IDs, named waypoints, safe durations,
     and a small maximum number of steps
   - invalid plans fall back to existing GOAP goal behavior
   - add autonomous idle behavior with a conservative probability/cooldown so the
     character occasionally wanders but does not spam or interrupt player commands.

7. Add automated Godot tests runnable headless:
   - one patrol command produces multiple distinct position targets in route order
   - wander target is within safe bounds
   - TV and existing gesture tests do not regress
   - invalid structured plans are rejected
   - action queues terminate (no hangs)
   Prefer deterministic logic tests plus a short scene integration test.

8. Update `CLAUDE.md` and add `docs/SPATIAL_AUTONOMY.md` describing:
   - cognition vs planning vs navigation vs animation
   - what is dynamic and what remains predefined
   - exact test commands
   - known limitations.

## Non-goals

- Do not install or download motion-generation models.
- Do not replace the penguin asset or regenerate GLBs.
- Do not redesign UI/furniture.
- Do not claim physical object interaction is complete.

## Acceptance

- Godot 4.6.1 parses and instantiates the main scene.
- Existing seven animations are present.
- “绕着整个房间转一圈” resolves to a multi-point patrol action.
- During a graphical run the penguin visibly changes world position while walk plays.
- No unrelated secrets or user files are touched.
