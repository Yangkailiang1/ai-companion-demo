# Save system and stateful objects

## v0.6 baseline

`SaveSystem` stores a versioned JSON snapshot at:

```text
user://world_save_v1.json
```

Schema version 1 contains:

- world time, day, time accumulator and Agent needs;
- each semantic object's state and structured properties;
- each loaded Agent's identity, position, rotation, activity and emotion.

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
```

The check verifies severe dehydration, semantic visibility, two-Agent position
restore, world-time restore, structured plant-state restore, and recovery through
the real `water` affordance.
