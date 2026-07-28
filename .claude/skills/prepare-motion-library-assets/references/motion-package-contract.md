# Motion package contract

## Accepted inputs

| Input | Role |
|---|---|
| `.npy` `(T,22,3)` | Preferred canonical HumanML3D source |
| `.bvh` | Skeleton animation staging; document hierarchy/rest pose/FPS |
| body-only `.vmd` | MMD staging; requires PMX bone convention inventory |
| animated `.fbx` / `.glb` | Staging; separate animation from bundled mesh |
| Light-T2M output | Candidate canonical source, never direct runtime control |

Reject files without license evidence, FPS, coordinate units, or a reproducible
mapping to a documented skeleton. Route facial-only VMD curves to the expression
pipeline.

## Canonical source

```text
shape: (T, 22, 3)
dtype: float32-compatible
current frame gate: 20..196
coordinate system, FPS and floor plane: explicitly recorded
```

## Reusable retarget output

```text
motion_package.json
source_positions.npy
target_rotations.npy
root_motion.npy
foot_contacts.npy
```

`motion_package.json` records source license/hash, action ID, description, aliases,
FPS, duration, loop, root policy, body layers, contact events, bone order, quaternion
order, and validation results.

## Catalog acceptance

- Source validates numerically: finite values, stable bone lengths, safe velocity.
- Root motion is separated; current Godot locomotion policy is `in_place`.
- Target bone map and rest-pose correction are versioned per skeleton family.
- Visual review covers facing, ground contact, foot sliding, loop seam, joint limits,
  clipping, and transition quality.
- Only the baked target clip name enters a character `clip_map`.
- Only shared semantic metadata enters `data/motion_catalog.json`.
