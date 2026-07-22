# Offline Motion Library

This project treats HumanML3D and Light-T2M output as an offline motion source, not
as a runtime dependency inside Godot.

## Contract

Input motion must be canonical HumanML3D joint positions:

```text
shape: (T, 22, 3)
dtype: float32-compatible
frames: 20..196 for the current safety gate
```

The retarget step writes a package directory:

```text
motion_package.json
source_positions.npy
target_rotations.npy
root_motion.npy
foot_contacts.npy
```

`target_rotations.npy` is ordered by `motion_package.json.runtime_contract.bone_name_order`.
Quaternions use `wxyz` order. Root translation is separated so Godot navigation can
remain in charge of world movement.

## Current Penguin Adapter

The first adapter uses `data/humanml3d_penguin_bone_map.json`. It maps HumanML3D's
22 canonical joints onto the penguin core body bones and emits reusable rotation
deltas. The package is intentionally not hardcoded to the penguin mesh: another
character can reuse the same source package by providing an equivalent target bone
map and a baker that aligns those target rest-pose bones to the package directions.

## Commands

Smoke fixture:

```bash
python3 motion_lab/scripts/make_humanml3d_fixture.py /tmp/hml_fixture.npy
python3 motion_lab/scripts/retarget_humanml3d_motion.py /tmp/hml_fixture.npy \
  --motion-id smoke_walk --text "fixture walk"
python3 motion_lab/scripts/validate_retarget_package.py motion_lab/generated/library/smoke_walk
```

Real Light-T2M/HumanML3D output uses the same commands, replacing the fixture path
with the generated `(T,22,3)` `.npy` file.

## Next Baking Step

The package is the reusable middle layer. The next production step is a Blender/Godot
baker that reads `target_rotations.npy`, applies each rotation delta to a concrete
target skeleton rest pose, keyframes the pose bones, and exports a reviewed GLB or
Godot animation clip. After visual review, the clip can be added to `motion_catalog.json`
and selected by the action router.

The first penguin baker is available at `tools/blender/bake_retarget_package.py`:

```bash
/Applications/Blender.app/Contents/MacOS/Blender --background \
  --python tools/blender/bake_retarget_package.py -- \
  --input-glb assets/characters/penguin/penguin.glb \
  --package motion_lab/generated/library/smoke_walk \
  --output-glb assets/characters/penguin/penguin.glb \
  --action-name offline_smoke_walk
```

For production clips, use a reviewed motion package and a semantic action name, then
add the exported clip to `data/motion_catalog.json` and `PerformanceCueTypes`.
