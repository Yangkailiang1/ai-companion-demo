---
name: prepare-character-model-assets
description: Audit, extract, convert, and normalize licensed character model packages into Godot-ready GLB character packages plus versioned runtime manifests, bone/morph/animation inventories, and provenance. Use for PMX/MMD, FBX, VRM, GLB, or GLTF humanoid and chibi models, when onboarding public or local-only characters, or when DeepSeek/Claude Code needs to batch-process character archives without coupling models to motion, expression, cognition, or story code.
---

# Prepare Character Model Assets

Read `CLAUDE.md`, `docs/roadmap/C-characters/C6-character-import.md`,
`docs/roadmap/O-opensource/O2-import-tools.md`, and
`references/character-package-contract.md`.

## Workflow

1. Limit one batch to three models from the same source format and skeleton family.
2. Audit the official license before extraction. Classify each model as:
   - `public_redistributable`: license permits modification and redistribution;
   - `local_only`: user may convert locally but neither source nor output enters Git;
   - `rejected`: missing, conflicting, research-only, or prohibited game-use terms.
3. Inventory archives in quarantine. Reject traversal paths, executables, nested
   archives, missing textures, encrypted files, and unexplained binary plugins.
4. Prefer a self-contained GLB. Accept GLTF with dependencies. Convert FBX/PMX/MMD
   offline in Blender; PMX and VRM are not assumed to be native Godot runtime formats.
5. Preserve one mesh hierarchy, one `Skeleton3D`, material textures, blend shapes,
   and embedded animation tracks. Do not rename bones or morphs before inventorying
   their original names.
6. Export normalized public packages to `assets/characters/<character_id>/`.
   Export restricted packages only to ignored `assets/local_characters/<character_id>/`.
7. Produce:
   - `model.glb`;
   - `provenance.json`;
   - `character_intake.json` conforming to
     `data/asset_pipeline/schemas/character_intake.schema.json`;
   - bone, morph, material, and embedded-animation inventories;
   - a version-1 manifest based on
     `data/examples/chibi_character_manifest.example.json`;
   - a conversion report containing source/output hashes and warnings.
8. Map bones only to shared semantic aliases. Inventory embedded clips but hand clip
   normalization to `$prepare-motion-library-assets`. Inventory morphs but hand
   semantic facial mapping to `$prepare-expression-library-assets`.
9. Import in Godot, then verify scale, forward/up axes, floor contact, skeleton pose,
   material/alpha correctness, collision dimensions, and absence of a T-pose idle.
10. Run character adapter and runtime-binding checks. Report failures per character;
    never let one broken package invalidate accepted siblings.
11. Before handoff, run `tools/assets/validate_character_intake.py` for every package.
    Treat missing files, malformed inventory JSON, SHA/license mismatch, or any
    `res://` traversal/symlink escape as a per-character failure.

## Boundaries

- Do not copy cognition, memory, StoryDirector, GOAP, or UI code per character.
- Do not put model-specific bone/morph names into shared motion or expression catalogs.
- Do not declare an embedded animation usable merely because its name exists.
- Do not commit, push, edit `data/llm_config.json`, or move restricted assets into
  tracked paths. Codex owns final visual acceptance and Git operations.

## Guardrails

- **License fail-closed**: Automation must never promote a license from
  `unknown` or `local_only` to `allowed` / `public_redistributable`. If the
  source license is unknown or private, the output provenance must preserve
  `redistribution: local_only` (or equivalent). Do not fabricate placeholder
  URLs like `github.com/your-org/...`.
