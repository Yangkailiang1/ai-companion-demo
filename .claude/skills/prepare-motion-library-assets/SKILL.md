---
name: prepare-motion-library-assets
description: Audit, normalize, validate, retarget, and package licensed body-motion assets as character-independent motion records and reviewed character-specific baked clips. Use for HumanML3D or Light-T2M NPY output, BVH, VMD body motion, FBX/GLB animation, Mixamo-like clips, or embedded character animations when building the shared action library without coupling source motion to a specific mesh, expression set, LLM, or Godot scene.
---

# Prepare Motion Library Assets

Read `CLAUDE.md`, `docs/roadmap/C-characters/C2-motion-library-retargeting.md`,
`docs/OFFLINE_MOTION_LIBRARY.md`, and `references/motion-package-contract.md`.

## Workflow

1. Limit one batch to five clips from one provider, license, skeleton convention,
   and frame-rate family.
2. Resolve per-clip redistribution and derivative-animation rights. Quarantine
   unknown, research-only, account-locked, or no-redistribution sources.
3. Separate body motion from meshes, textures, audio, cameras, facial tracks, and
   scene objects. Route facial-only curves to `$prepare-expression-library-assets`.
4. Normalize each clip into one character-independent source:
   - preferred: HumanML3D joint positions `(T, 22, 3)`, float32-compatible NPY;
   - accepted staging: BVH, body-only VMD, or FBX/GLB animation with documented
     skeleton, rest pose, axes, units, FPS, and root track.
5. Assign a stable semantic `action_id`, bilingual aliases, description, tags,
   duration, loop flag, body layers, contact events, and root-motion policy.
6. Run `motion_lab/scripts/validate_motion.py`. For canonical NPY also run the
   retarget and package validators documented in `docs/OFFLINE_MOTION_LIBRARY.md`.
7. Write the reusable retarget package separately from every target character.
   Quaternions use `wxyz`; root translation and foot contacts stay separate.
8. For each skeleton family, apply a reviewed semantic bone map and rest-pose
   correction, bake a target-specific clip in Blender, and export it in-place.
   Navigation remains authoritative for world translation.
9. Inspect foot sliding, facing, joint limits, loop seams, hand/body clipping,
   ground contact, start/stop blending, and actual Godot playback.
10. Promote only accepted clips to `data/motion_catalog.json` and the relevant
    character `clip_map`. Report rejected clips and reasons without hiding them.

## Boundaries

- Never map source joint arrays directly onto arbitrary target bone rotations.
- Never modify a character mesh, expression map, LLM prompt, scene recipe, or physics.
- Generated Light-T2M output is a candidate, not production motion until baked and
  visually reviewed.
- Do not commit or push. DeepSeek prepares deterministic artifacts and evidence;
  Codex owns acceptance and catalog promotion.
