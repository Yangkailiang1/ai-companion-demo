# Character runtime adapters

Motion and expression libraries are shared semantic layers, but each character needs
a model-specific adapter.

```text
motion_query / expression_query
  -> shared router
  -> action_id / expression payload
  -> character adapter
  -> model-specific playback
```

Runtime adapter config:

```text
data/character_runtime_adapters.json
```

The adapter has two separate mapping layers:

- `motion_adapter.clip_map`: maps a shared action id/gesture to the clip or safe
  fallback this model can actually play.
- `skeleton_adapter`: maps shared semantic bones (`head`, `left_upper_arm`, etc.) to
  imported skeleton bone names, then applies a natural rest pose and lightweight
  runtime overlays while true retargeted clips are still missing.
- `expression_adapter.channel_map`: maps shared expression-library channels such as
  `joy`, `blink`, and `a/i/u/e/o` to this model's imported blend-shape names.

## Current adapters

### 咕咕嘎嘎 (`main_agent`)

- Motion: real `AnimationPlayer` clips from `penguin.glb`.
- Expression: blend shapes such as `joy`, `angry`, `blink`, `a/i/u/e/o`.
- Skeleton overlay: disabled because this character already has reviewed clips; the
  overlay should not fight the `AnimationPlayer`.
- This is the current best-supported character.

### 诀 (`jue_agent`)

- Motion: procedural fallback on `JueModelRoot`.
- Skeleton pose: `Bip001_*` bones are mapped to shared semantic bones. The runtime
  overlay provides lightweight head/chest idle breathing and cue-driven body accents.
  Large T-pose-like VFX/sleeve display pieces are hidden in the demo until their cloth
  bones are properly retargeted.
- Expression: imported FBX exposes morph targets, but channel names do not yet fully
  match the shared expression library. The adapter therefore provides broad aliases
  and safely ignores channels that are not present on the imported mesh.
- Current verified morph channels are eyebrow-oriented:
  `S_actor_jsspsi_brow_01_LX`, `S_actor_jsspsi_brow_01_RX`,
  `S_actor_jsspsi_eyebrow_01_L_close`, and
  `S_actor_jsspsi_eyebrow_01_R_close`.
- The model currently has no imported `AnimationPlayer` clips in Godot.

The HumanML3D-to-Jue 22-joint semantic map is recorded in:

```text
data/humanml3d_jue_bone_map.json
```

This means 诀 can respond to routed actions, but actions like `wave` are not yet
true arm-bone animations. They are visible root/body gestures until we retarget
motion-library clips to her skeleton.

## Next real motion step

To truly use the offline motion library across models:

1. Normalize shared action ids (`wave`, `nod`, `walk`, etc.).
2. For each model, define a skeleton map and rest-pose correction.
3. Bake each action id into character-specific animation clips.
4. Export those clips into Godot as `AnimationPlayer` animations.
5. Keep the LLM/router layer unchanged.

This keeps intelligence and asset adaptation separate:

```text
LLM/router chooses "wave"
咕咕嘎嘎 adapter plays penguin wave clip
诀 adapter plays Jue-retargeted wave clip
```

## Validation

Run the adapter coverage check after importing a new character or editing any mapping:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script scripts/debug/character_adapter_coverage_check.gd
```

It verifies:

- each character has a runtime adapter;
- action ids map to available clips or declared fallbacks;
- skeleton semantic aliases resolve to real `Skeleton3D` bones;
- expression semantic channels map to at least one real blend shape;
- `data/humanml3d_jue_bone_map.json` contains exactly 22 source joints and all
  targets exist in Jue's imported skeleton.
