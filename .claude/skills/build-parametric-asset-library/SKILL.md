---
name: build-parametric-asset-library
description: Normalize audited GLB/GLTF/OBJ/FBX asset batches into a Godot parametric scene Asset Registry with stable IDs, provenance, measured AABBs, axes, style tags, budgets, physics roles, semantic capabilities, and preview validation. Use after a licensed archive has passed download-open-3d-assets, when converting local itch.io/KayKit packs, or when preparing furniture and props for deterministic Scene Recipes. Use godot-import-interactable-object for objects that become interactable.
---

# Build Parametric Asset Library

Read `CLAUDE.md`, the S4 roadmap, `docs/ASSET_PIPELINE_CONTRACTS.md`, and
`references/registry-contract.md`. Accept only artifacts accompanied by an approved
provenance manifest.

## Workflow

1. Limit the batch to three assets of one archetype/style. Prefer GLB, then GLTF with
   all dependencies; use OBJ/FBX only when conversion is required.
2. Extract only selected files into a task staging directory. Preserve atlas textures
   and `.bin` dependencies. Never bulk-extract an entire marketplace pack into `res://`.
3. Normalize names to stable snake_case IDs and copy accepted source files under
   `assets/props/<provider>/<pack>/<asset_id>/`.
4. Measure the imported AABB and inspect front/up axes in Godot or Blender. Record
   native dimensions before applying any scene scale.
5. Assign independent capabilities:
   - visual role: structure, furniture, decor, clutter, lighting;
   - physics role: none, static, rigid, trigger;
   - semantic capabilities: observable, interactable, stateful, portable;
   - placement: floor, wall, surface, ceiling, modular_grid.
6. Write Registry candidates and run `scripts/validate_registry_batch.py`.
7. Build an isolated preview showing all three assets with labels and a meter grid.
   Run `Godot --headless --import --path .` to completion before runtime validation;
   a timed editor scan may abort before GLTF import caches exist. Verify material,
   scale, front/back, origin, floor contact and shadows with Metal.
8. Promote interactable candidates through `$godot-import-interactable-object`.
   Visual-only items must not enter `SemanticWorld`; obstacles need collision/nav
   metadata without affordances.
9. Add candidates to Scene Recipes only after collision, navigation and deterministic
   seed tests pass. Keep the current living room unchanged until preview parity passes.
10. Update S4/S3/T2 roadmap nodes and provenance. Codex owns visual acceptance,
    commit and push.

Do not invent dimensions, axes, affordances or licenses. Stop when dependencies,
material ownership or intended interaction semantics are ambiguous.

Do not ingest rigged characters, body animations, facial morph packs, cameras, audio,
or scripts. Those are separate character/motion/expression pipelines and must not
appear as scene Registry assets.

## Guardrails

- **Source ID ≠ normalized ID**: The provider's asset ID (e.g. `WoodenTable_01`)
  may differ in case from the project's normalized ID (e.g. `woodentable_01`).
  Scripts must resolve quarantined sources by source ID, then write targets
  under the normalized ID. The Registry entry must record both.
- **Atomic target creation**: Never `rmtree(target)` before verifying the source
  directory, GLTF, `.bin` companion, and provenance manifest all exist. Use a
  task-local temp directory for staging, then atomically rename into place.
- **No machine paths**: Public manifests and Registry candidates must use
  `res://`-style resource paths or project-relative paths. Never write
  `/Users/...`, `/private/tmp/...`, or similar absolute paths.
- **Idempotency**: Running the normalization script twice must produce identical
  output files with identical hashes.
- **Style is visual evidence**: Provider tags and filenames do not prove a coherent
  batch. Compare silhouette, era, material and proportions in the shared preview;
  retain individually valid but mismatched assets as candidates instead of accepting
  them as one production style set.
- **Bind review to content**: Store measured geometry and preview status with the
  reviewed source SHA-256. A changed binary under the same asset ID returns to
  `inventoried`; never reuse old axes, bounds or visual acceptance by filename alone.
