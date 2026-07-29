# X1.2 Cross-location Save Schema v2 — bounded implementation

Read `CLAUDE.md`, `docs/roadmap/X-engineering/X1-save-migration.md`,
`docs/roadmap/S-world/S2-multi-room-town.md`, `docs/SAVE_AND_OBJECT_STATE.md`,
and these implementations/tests before editing:

- `scripts/core/save_system.gd`
- `scripts/core/semantic_world.gd`
- `scripts/environments/world_location_loader.gd`
- `scripts/environments/parametric_room_runtime.gd`
- `scripts/debug/save_plant_state_check.gd`
- `scripts/debug/multi_room_home_check.gd`

Implement only the X1 cross-location persistence slice. Do not change default
world mode, scenes, recipes, registries, models, UI, cognition, stories, LLM
configuration, project.godot, docs/roadmap, Git, or `.uid` files.

## Allowed output files

1. `scripts/core/save_system.gd`
2. `scripts/core/semantic_world.gd`
3. `scripts/environments/parametric_room_runtime.gd`
4. `scripts/debug/cross_location_save_check.gd`

No other file may be modified or created.

## Save schema v2

- Set `SCHEMA_VERSION = 2`.
- New default is `user://world_save_v2.json`.
- Preserve automatic/manual migration from v1:
  - explicit v1 files must load;
  - automatic load should prefer v2 and fall back to existing
    `user://world_save_v1.json`;
  - migration is in memory and the next save writes v2;
  - unknown future schemas fail closed before mutating runtime.
- Add top-level:

```json
"location": {
  "world_mode": "parametric",
  "location_id": "kitchen"
}
```

- Every saved agent state includes `location_id`.
- Do not store NodePath, absolute filesystem paths, model paths, or Godot object
  references.

## Restore ordering

1. Parse and validate/migrate the snapshot without mutating runtime.
2. Resolve `scenes/main.tscn/WorldRoot` as `WorldLocationLoader`.
3. Restore the saved world mode/location before importing semantic state or
   applying agent transforms:
   - `parametric`: call `travel_to(location_id)`;
   - `legacy`: call `switch_location("legacy")`;
   - missing/unknown location fails without replacing the current room.
4. Import world, semantic, psychology and pending agent states.
5. Apply an agent transform only when its saved `location_id` equals the active
   location. Keep unmatched entries pending.
6. `ParametricRoomRuntime` currently applies declared spawn points after one
   physics frame. After that spawn phase, it must ask SaveSystem to apply the
   matching pending agent states, so declared spawns cannot overwrite a loaded
   position.

Expose a small public SaveSystem method for this final location-aware apply; do
not make ParametricRoomRuntime inspect SaveSystem internals.

## Deferred semantic object states

`SemanticWorld.import_save_state()` must retain valid saved states for objects
whose rooms have not been instantiated yet. When `upsert_generated_object()`
later registers that stable semantic ID, apply and consume its pending state.
`export_save_state()` must merge still-pending entries so travelling/saving
before room instantiation cannot erase them.

Malformed entries must be ignored per object, without clearing valid pending
states. A loaded state must never overwrite spatial/affordance/model metadata;
only `state` and `properties` are persistent.

## Dynamic acceptance test

Create `scripts/debug/cross_location_save_check.gd`, within the GDScript test
hard limit, that runs with Godot headless and uses only an isolated
`/private/tmp/ai_companion_cross_location_save_v2.json`.

It must prove:

1. parameteric living room → bedroom; change a bedroom object state;
2. travel to kitchen; change a kitchen object state and set both main/Jue
   positions; save while kitchen is active;
3. simulate a fresh semantic runtime by clearing registered semantic objects
   through an explicit test-only/public reset helper only if needed (do not
   directly reach private state from production code);
4. move to another room and mutate agent positions;
5. load v2 and verify active mode/location restore to parametric kitchen;
6. after the delayed spawn phase, both saved agent transforms restore;
7. kitchen object state restores immediately;
8. travel to bedroom and verify its previously unloaded object state restores
   from the deferred semantic store;
9. construct/load a minimal isolated v1 fixture and verify migration succeeds,
   `get_snapshot()` now reports schema 2, and no invalid cross-room teleport is
   introduced;
10. an unknown schema and an invalid saved location fail without replacing the
    active room.

Always remove temporary files, including on accumulated assertion failure.
Print exactly one success marker:

```text
CROSS_LOCATION_SAVE_PASS schema=2 location=kitchen
```

## Compatibility and quality

- Existing `save_plant_state_check.gd` must remain passing without edits.
- Existing `multi_room_home_check.gd` must remain passing without edits.
- No function over 60 lines. Keep modified production files below hard limits.
- New/modified functions require requirement IDs and side-effect comments per
  `CLAUDE.md`.
- Do not silently convert an invalid saved location to living_room.

## Required validation

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/cross_location_save_check.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/save_plant_state_check.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/multi_room_home_check.gd
wc -l scripts/core/save_system.gd scripts/core/semantic_world.gd \
  scripts/environments/parametric_room_runtime.gd \
  scripts/debug/cross_location_save_check.gd
git diff --check
```

Return changed files, exact exit codes, markers, and unresolved ambiguity. Do
not update docs or claim the default parameterized mode is ready.
