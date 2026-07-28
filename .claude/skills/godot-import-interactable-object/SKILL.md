---
name: godot-import-interactable-object
description: Import or batch-onboard licensed GLB/GLTF/OBJ 3D props into this Godot project as complete interactable objects with measured transforms, collision, navigation-safe anchors, SemanticWorld metadata, affordances, save-state coverage, headless tests, and visual QA. Use for adding furniture, decorations, consumables, devices, containers, seats, or other scene props; also use when auditing an existing prop that is only visual or when converting a validated single-object workflow into batch production.
---

# Godot Import Interactable Object

Use the repository root containing `project.godot`. Read `CLAUDE.md` and the relevant
`S3`, `T2`, and `C4` roadmap nodes before editing.

## Workflow

1. Resolve the asset license before importing. Reject unknown or non-redistributable
   assets from tracked public paths. Record source URL, license and entry resource.
2. Measure the unmodified model AABB and inspect its front/up axes. Never reuse a
   transform from another asset. Run the existing bounds probe or add the asset to it.
3. Create `data/interactable_objects/<object_id>.json` using the contract in
   [references/object-contract.md](references/object-contract.md). Run:

   ```bash
   python3 .claude/skills/godot-import-interactable-object/scripts/validate_interactable_spec.py \
     data/interactable_objects/<object_id>.json --project-root .
   ```

4. Choose the physics root:
   - `StaticBody3D`: fixed furniture, wall decoration, built-in appliance.
   - `RigidBody3D`: portable or throwable prop; start frozen when placed.
   - A dedicated state component: plant, TV, light, door, container, or other stateful
     object. Keep state logic out of `InteractableObject`.
5. Instance the imported model below the physics root. Add an explicit primitive
   collision shape; never generate concave dynamic collision for small props.
6. Add `AnchorApproach` and `AnchorLook`. Add `AnchorLeftHandGrab`,
   `AnchorRightHandGrab`, `AnchorPlace`, or `AnchorSit` when the affordances require
   them. Approach anchors must be on the floor, inside room bounds, outside collision,
   and reachable by NavMesh.
7. Attach `scripts/objects/interactable_object.gd`, set stable `object_id`,
   `object_name`, and `interaction_point`. Add the matching descriptor to
   `data/scene_config.json`; positions must agree with live anchors.
8. Implement only declared affordances. Return `{handled, success, reason}` for
   stateful/physical handlers. Failed interactions must not mutate state or apply
   effects. Do not bypass `ActionExecutor` or `SemanticWorld`.
9. Verify save export/import for state and properties. Add a headless contract test
   covering model, license, collision, anchors, descriptor binding, affordance result,
   failure behavior, and save round-trip.
10. Render with Metal and visually inspect scale, front/back orientation, wall/floor
    contact, shadows, clipping, and approach clearance. A headless pass alone is not
    acceptance.
11. Update the roadmap and provenance docs. Keep downloaded asset license rules and
    local-only character isolation intact.

## Batch rules

- First complete one golden object and have Codex review its headless and visual
  evidence. Only then create siblings of the same archetype.
- Batch by archetype: decor, static furniture, portable rigid prop, stateful device,
  container, or seat. Do not mix archetypes in one unreviewed batch.
- Limit a batch to three objects. Report every modified file and test result.
- Do not edit `data/llm_config.json`, model binaries already under review, unrelated
  `.uid` files, or Git history. Do not commit or push; Codex owns acceptance.
- Stop and report when license, model axes, scale, collision, or anchor placement is
  ambiguous. Never guess an asset license.

The validated reference implementation is `wall_art` in `living_room.tscn`, covered by
`scripts/debug/interactable_asset_pipeline_check.gd`. It demonstrated why AABB and
front-face inspection are mandatory: the first reused rotation passed semantic tests
but rendered like a horizontal shelf, and the first front axis showed the frame back.
