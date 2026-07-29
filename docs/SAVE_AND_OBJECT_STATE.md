# Save system and stateful objects

## Schema v2 cross-location baseline

`SaveSystem` stores a versioned JSON snapshot at:

```text
user://world_save_v2.json
```

Schema version 2 contains:

- the active `world_mode` and `location_id`;
- world time, day, time accumulator and Agent needs;
- independent needs for each known `agent_id` (with the original main-Agent field
  retained for backward-compatible saves and HUD access);
- each semantic object's state and structured properties;
- each loaded Agent's identity, location, position, rotation, activity and emotion;
- each Agent's persistent mood, attention, intention, recent activities, private
  thought buffer, current daily plan and uncertain beliefs about other characters.

The loader restores the location before applying world, object, and Agent state.
Object state for unloaded rooms remains pending until that room's generated objects
register with `SemanticWorld`. Agent transforms are applied once, after the target
room's cast has spawned, then consumed.

Version 1 remains readable: `user://world_save_v1.json` is used as a fallback when
the v2 default does not exist and is migrated in memory to `legacy/living_room`.
Unknown schemas, invalid locations, and malformed Agent/object records are rejected
before the active room is replaced.

The runtime attempts to load the default save after the startup scene is ready and
autosaves every 60 seconds. Tests can pass an explicit path to `save_game()` and
`load_game()` so they never overwrite a player's normal save.

## Stateful object contract

`SemanticWorld.ObjectData` now has a `properties` dictionary in addition to the
human-readable `state`. Stateful scene components update both through:

```gdscript
SemanticWorld.update_object_properties(object_id, properties, state_name)
```

The text snapshot includes both description and current state. This is important:
the LLM should read “绿植小绿（严重缺水）” instead of only seeing a static description.

## Plant prototype

`PlantState` is the first reusable stateful-object implementation:

- moisture decreases each game hour;
- health decreases while severely dry and recovers in a healthy moisture range;
- growth advances after 24 accumulated healthy game hours;
- `water` and `prune` affordances update structured state;
- model scale/lean and a world-space status label provide visual feedback;
- moisture, health, growth stage and healthy-hour progress survive save/load.

The same pattern should be reused for milk tea, books, television, doors and
containers rather than adding object-specific logic to `CognitiveCycle`.

## Validation

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/save_plant_state_check.gd

/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/cross_location_save_check.gd
```

The first check verifies severe dehydration, semantic visibility, two-Agent position
restore, world-time restore, structured plant-state restore, and recovery through
the real `water` affordance. The cross-location check verifies kitchen/bedroom
object state, two-Agent one-shot transform restoration, deferred room state, v1
migration, same-room reload, and fail-closed behavior for malformed snapshots.
