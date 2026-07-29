# P2.1/P2.3/P2.4 observer + first-person controller — bounded implementation

Read completely:

- `CLAUDE.md`
- `docs/roadmap/P-player/P2-control-camera.md`
- `docs/roadmap/P-player/P3-player-interaction.md`
- `docs/roadmap/S-world/S2-multi-room-town.md`
- `scripts/camera/orbit_room_camera.gd`
- `scripts/environments/world_location_loader.gd`
- `scripts/environments/world_location_catalog.gd`
- `scripts/ui/chat_input.gd`
- `scripts/debug/camera_orbit_check.gd`
- `scripts/debug/world_travel_portal_check.gd`
- `scenes/main.tscn`
- `data/world_locations.json`

Implement only the asset-independent observer/first-person player-control
vertical slice. Do not implement a third-person avatar, download assets, change
AI/character behavior, change save schema, edit chat_input.gd, change the
default world mode, update roadmap docs, run Git, or touch unrelated `.uid`
files.

## Product truth

- There is no public player avatar asset yet. Do not render a capsule/cylinder
  person and do not reuse an AI character model as the player.
- Keep the current room-center orbit camera as the default observer/director
  mode.
- Add a persistent invisible `CharacterBody3D` player collision body under
  `WorldRoot`. It is a control substrate, not a finished avatar.
- Add an asset-independent first-person mode. The body later becomes the parent
  for a user-selected third-person visual.
- The existing clickable portals remain valid in both modes. Do not add fake
  proximity checks.

## Required architecture

Prefer these small modules:

1. `scripts/player/player_first_person_controller.gd`
   - Owns CharacterBody3D movement, gravity, floor contact and collision.
   - WASD movement is relative to the active camera's horizontal basis.
   - Exposes typed public methods such as `set_control_enabled`,
     `teleport_to_floor_position`, `get_eye_global_position`, and a read-only
     control-state query.
   - When text input is focused, it must stop horizontal velocity immediately.
   - It does not choose camera mode, load rooms, access UI node paths, or travel.

2. Refactor `scripts/camera/orbit_room_camera.gd`
   - Add stable string modes `observer` and `first_person`; observer remains
     default and preserves current orbit/zoom/Q-E behavior.
   - Public `set_view_mode(mode) -> bool` and `get_view_mode() -> String`.
   - `V` toggles modes unless a LineEdit/TextEdit is focused.
   - First-person uses the persistent body eye position and captures the pointer;
     plain mouse motion updates yaw/pitch without holding a button.
   - Escape releases the system pointer without leaving first person. Right-click
     on non-UI world space recaptures it; left click remains free for portals.
   - Entering first person releases existing GUI focus once; clicking/focusing
     chat afterwards blocks movement, view drag, V toggle and keyboard camera.
   - Returning to observer restores the prior observer target/distance/yaw/pitch.
   - Emit `view_mode_changed(mode)`; never directly mutate ChatInput.
   - Preserve `_is_pointer_over_ui` protection.

3. `scripts/ui/player_camera_hint.gd`
   - Attach to the existing CameraHint label.
   - Listen to the camera's public signal and display concise mode-specific
     controls. UI may query the camera public API; camera must not depend on UI.

`main.tscn` should add `PlayerBody` with a CapsuleShape3D collision and the new
controller script. Do not add a visible MeshInstance3D.

## Cross-location entry contract

- `WorldLocationLoader` owns entry resolution.
- After the new room is added, teleport `PlayerBody` to the selected entry floor
  coordinate. The controller applies its standing-height offset and clears
  velocity.
- Stop overriding the AI `Agent` spawn with the player entry. AI agents should
  use each location's declared `cast_spawns`; this corrects the old observer-era
  conflation of player and companion.
- Legacy mode gets a safe living-room floor spawn.
- Portal nodes still know only `exit_id`.

Do not add player persistence in this slice; record that as the next X1/P2 task.

## Dynamic acceptance

Create `scripts/debug/player_first_person_check.gd` under 250 lines. It must
instantiate `main.tscn`, disable autonomous scheduling, and prove:

1. `PlayerBody` exists under WorldRoot, has CharacterBody3D +
   CapsuleShape3D, and no MeshInstance3D descendant.
2. default mode is observer; the existing orbit path still moves the camera.
3. invalid view mode is rejected without changing state.
4. switching to first person enables body control and places the camera at the
   eye.
5. simulated W input moves the body on the generated room floor, while wall and
   furniture collision keep it inside room bounds.
6. focusing the existing LineEdit releases the pointer and immediately prevents
   movement/mouse look; V cannot toggle while text is focused.
7. after releasing focus, V returns to observer and body control disables.
8. travel living→kitchen places PlayerBody at `from_living`, while `Agent`
   remains at the kitchen's declared cast spawn (not at the player entry).
9. travel kitchen→living continues to work and first-person can be re-entered.
10. CameraHint text changes with mode and capture/release state.
11. entering first person captures the mouse, plain motion rotates, Escape
    releases it, released motion is ignored, and right-click recaptures it.

Also update:

- `scripts/debug/world_travel_portal_check.gd` to assert `PlayerBody` uses the
  kitchen entry instead of asserting `Agent` does.
- `scripts/debug/camera_orbit_check.gd` only as required for the explicit
  observer default and focus contract.

Print exactly on success:

```text
PLAYER_FIRST_PERSON_PASS modes=2 collision=true travel=true
```

## Quality and validation

- Follow all CLAUDE.md headers, per-function roadmap comments and budgets.
- No new/modified function over 60 lines; target 40.
- Runtime files under 300 lines; tests under 250.
- Avoid project.godot InputMap edits; raw physical key checks are acceptable
  for this bounded keyboard baseline.
- Do not leak target location data into PlayerBody or camera.
- Do not use test-only movement methods in runtime.

Run with explicit log files:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --log-file \
  /private/tmp/player_first_person.log --path . \
  --script res://scripts/debug/player_first_person_check.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --log-file \
  /private/tmp/camera_orbit.log --path . \
  --script res://scripts/debug/camera_orbit_check.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --log-file \
  /private/tmp/world_travel_portal.log --path . \
  --script res://scripts/debug/world_travel_portal_check.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --log-file \
  /private/tmp/cross_location_save.log --path . \
  --script res://scripts/debug/cross_location_save_check.gd
git diff --check
```

Return changed files, command exit codes, exact markers and unresolved issues.
Do not update docs and do not commit.
