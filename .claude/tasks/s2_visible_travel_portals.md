# S2.2 Visible travel portals — bounded implementation

Read `CLAUDE.md`, `docs/roadmap/S-world/S2-multi-room-town.md`,
`docs/roadmap/S-world/S4-parametric-generation.md`, and:

- `data/world_locations.json`
- `scripts/environments/world_location_catalog.gd`
- `scripts/environments/world_location_loader.gd`
- `scripts/environments/parametric_room_runtime.gd`
- `scripts/environments/parametric_scene_builder.gd`
- `scripts/debug/multi_room_home_check.gd`
- `scripts/debug/camera_orbit_check.gd`

Implement only the S2.2 visible-door/player-travel vertical slice. Do not change
default world mode, character behavior, cognition, save schema, UI chat,
models, registries, LLM configuration, project.godot, roadmap docs, Git, or
unrelated `.uid` files.

## Player/runtime truth

There is currently no movable player avatar. The player is an orbit camera plus
UI. Do not implement fake proximity logic. The playable contract for this slice
is a world-space clickable 3D portal:

1. each declared valid exit has one visible warm wooden doorway/door leaf;
2. it has a CollisionObject3D picking volume and world-space label;
3. left-click activation emits a typed travel request using its stable exit ID;
4. hover/press provides clear visual feedback;
5. camera right/middle drag and chat input focus remain unchanged;
6. activation delegates to `WorldLocationLoader.travel_via(exit_id)`; the portal
   must never select a target scene or location directly.

The current runtime moves the shared Cast with the loaded room. Do not claim or
implement independent off-screen Agent migration in this slice.

## Declarative contract

Extend each exit in `data/world_locations.json` with a `portal` presentation
block. Required fields:

```json
"portal": {
  "semantic_id": "door_to_kitchen",
  "display_name": "通往厨房",
  "position": [-3.82, 1.1, 2.2],
  "rotation_deg": [0.0, 90.0, 0.0],
  "size": [1.25, 2.2],
  "label": "厨房"
}
```

Use stable snake_case semantic IDs unique within each location. Positions must
sit against visible side walls and must not overlap major furniture. Add
corresponding `type: door` openings to the living-room, kitchen, and bedroom
Recipes, then regenerate their checked-in Manifests with the existing compiler.
Do not hand-edit generated hashes. The builder currently supports one opening
per wall, so place at most one portal on each wall.

Strengthen `WorldLocationCatalog.load_catalog()` so malformed portal blocks,
non-vector positions/rotations, invalid sizes, missing labels/IDs, and duplicate
portal semantic IDs fail closed without publishing a partial catalog.

## Module shape

Prefer two small new files:

- `scripts/environments/world_travel_portal.gd`: one portal visual, picking,
  hover state, semantic interaction and `travel_requested(exit_id)` signal.
- `scripts/environments/world_portal_assembler.gd`: reads already validated
  exit presentation data and creates portals; never loads the catalog itself.

`ParametricRoomRuntime.configure_location()` retains a deep copy of exits.
After the generated room exists, it assembles portals and forwards their travel
request as a runtime signal. `WorldLocationLoader` connects that signal before
adding the room and handles it through `travel_via()`.

Register each portal in `SemanticWorld` with its stable ID, current
`location_id`, description, interaction point, and `traverse` affordance.
`perform_interaction("traverse", agent_id)` may emit the same request, but no
planner integration is required here. Unsupported verbs fail without travel.

Do not put direct `WorldLocationLoader` lookups inside a portal.

## Dynamic acceptance

Create `scripts/debug/world_travel_portal_check.gd` under the test hard limit.
It must instantiate `main.tscn`, switch to parameterized mode, and prove:

1. living room has exactly two portals with stable IDs, labels, visible meshes,
   CollisionShape3D, and `traverse` semantic affordance;
2. invalid verbs do not travel;
3. activating the kitchen portal through its public interaction API travels to
   kitchen and uses the declared entry;
4. kitchen has exactly one return portal; activating it returns to living room;
5. activating the bedroom portal travels to bedroom and the return works;
6. a double activation or activation from a retiring/stale portal cannot cause
   a second unexpected trip;
7. malformed isolated catalog fixtures fail closed;
8. no target location ID or scene path is owned by the portal node.

Print exactly:

```text
WORLD_TRAVEL_PORTAL_PASS locations=3 traversals=4
```

Update `multi_room_home_check.gd` only if needed to assert portal counts without
duplicating the full new contract.

## Quality

- Follow all file/function budgets in `CLAUDE.md`; no function over 60 lines.
- Every new/modified function needs roadmap comments and side-effect notes.
- New runtime files need the required responsibility header.
- Use procedural BoxMesh/StandardMaterial3D/Label3D only; no asset download.
- Avoid autoload or UI changes.
- Preserve invalid-travel atomicity and X1.2 cross-location saves.

## Required validation

Use `--log-file /private/tmp/<name>.log` for every Godot command:

```bash
python3 -m unittest tests.scene_generation.test_compile_scene_recipe
/Applications/Godot.app/Contents/MacOS/Godot --headless --log-file \
  /private/tmp/world_travel_portal.log --path . \
  --script res://scripts/debug/world_travel_portal_check.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --log-file \
  /private/tmp/multi_room_home.log --path . \
  --script res://scripts/debug/multi_room_home_check.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --log-file \
  /private/tmp/cross_location_save.log --path . \
  --script res://scripts/debug/cross_location_save_check.gd
git diff --check
```

Return changed files, commands/exit codes, success markers, and any unresolved
visual ambiguity. Do not edit roadmap docs or commit.
