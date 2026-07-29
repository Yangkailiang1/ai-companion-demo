---
name: prepare-expression-library-assets
description: Audit and normalize facial blend shapes, morph targets, facial bones, visemes, and facial animation assets into shared semantic expression entries plus per-character channel maps. Use for GLB/GLTF/VRM/FBX morphs, PMX/MMD morph inventories, facial VMD, ARKit-like channels, or character expression packs when building expressions and lip-sync without coupling them to body motion, meshes, LLM prompts, or scenes.
---

# Prepare Expression Library Assets

Read `CLAUDE.md`, `docs/roadmap/C-characters/C3-expression-body-language.md`,
`docs/EXPRESSION_ROUTER.md`, and `references/expression-package-contract.md`.

## Workflow

1. Limit one batch to three characters or one facial-expression pack sharing a
   naming convention.
2. Resolve license and redistribution rights. Keep restricted PMX/MMD/VRM-derived
   assets and conversion output in ignored local-only directories.
3. Inventory original blend-shape, morph, facial-bone, viseme, and facial-animation
   names before renaming or merging anything. Record the owning mesh for each channel.
4. Separate expression assets from body animation. Route body VMD/BVH/animation
   tracks to `$prepare-motion-library-assets`.
5. Map model-specific channels to shared semantics such as `neutral`, `joy`,
   `angry`, `sad`, `surprised`, `shy`, `bored`, `confused`, `blink`, and
   `a/i/u/e/o`. Preserve multiple aliases per semantic channel.
6. Mark every channel as `native`, `composite`, `bone_fallback`, `approximate`, or
   `unsupported`. Never claim support based only on a similar name.
7. Add reusable expression descriptions, aliases, weights, fade timing, and hold
   timing to `data/expression_library.json`. Put concrete morph names only in the
   character `expression_adapter.channel_map`.
8. Validate mappings against live Godot meshes. Test positive weights, reset to
   neutral, crossfade, missing-channel degradation, blinking, and mouth visemes.
9. Render close-up screenshots or a short preview for each accepted character.
   Check eyelid inversion, double transforms, stuck expressions, clipping, and
   material transparency.
10. Report coverage per semantic channel and keep unsupported entries explicit.

## Boundaries

- Do not bake body gestures into expression assets.
- Do not put model-specific morph names in the shared expression library.
- Do not treat head-bone fallback as a native facial morph.
- Do not edit cognition, story, scene geometry, or motion clips; do not commit or
  push. Codex owns final visual acceptance and adapter promotion.

## Guardrails

- Treat a standalone `expression_adapter.candidate.json` as metadata only. Runtime
  support exists only after its aliases enter the character manifest consumed by
  `CharacterAdapterRegistry`.
- Compare every candidate with the same character's current runtime manifest. Preserve
  verified aliases and fail the batch on any supported-to-unsupported regression.
- Script success and name matching are not facial acceptance. Require live mesh weight,
  neutral reset, crossfade and close-up visual evidence before `accepted`.
