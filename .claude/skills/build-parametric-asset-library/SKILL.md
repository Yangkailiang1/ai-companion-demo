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
