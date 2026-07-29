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
- `motion_adapter.locomotion_profile`: defines reference speed, stride length,
  playback bounds, start/stop blend and the mandatory `in_place` root-motion policy.
- `skeleton_adapter`: maps shared semantic bones (`head`, `left_upper_arm`, etc.) to
  imported skeleton bone names, then applies a natural rest pose and lightweight
  runtime overlays while true retargeted clips are still missing.
- `expression_adapter.channel_map`: maps shared expression-library channels such as
  `joy`, `blink`, and `a/i/u/e/o` to this model's imported blend-shape names.

## Current adapters

### 咕咕嘎嘎 (`main_agent`)

- Motion: real `AnimationPlayer` clips from `penguin.glb`.
- Idle: the runtime makes a local copy of the imported `idle` animation and applies
  a model-specific `-52°` local-X correction to both upper-arm tracks. This removes
  the source clip's T-pose silhouette without changing `walk`, `wave`, `happy`, or
  any other imported clip.
- Expression: blend shapes such as `joy`, `angry`, `blink`, `a/i/u/e/o`.
- Skeleton overlay: disabled because this character already has reviewed clips; the
  overlay should not fight the `AnimationPlayer`.
- This is the current best-supported character.
- Walk quality: native clip, with playback rate synchronized to actual horizontal
  velocity. The clip never owns world translation.

### 诀 (`jue_agent`)

- Asset: optional local FBX under `assets/local_characters/jue/`; public checkout keeps
  the same Agent contract with a redistributable primitive placeholder.
- Motion: additive semantic-skeleton fallback. `walk` now drives verified
  `Bip001_L/R_Thigh`, `Calf`, and `Foot` chains from actual traveled distance.
- Material: the LOD0 body, face, hair, iris and the first two clothing groups now
  use the FBX package's imported D/N/E textures. The runtime no longer replaces
  the whole outfit with guessed flat gray colors. Unretargeted VFX cloth groups
  remain hidden until their auxiliary bones and transparency are reviewed.
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

诀 now uses a character-specific additive skeleton overlay for lightweight
`idle`, `walk`, `wave`, `nod`, `think`, `happy`, and `talk` cues. It captures the FBX
import pose first and adds semantic-bone deltas on top, so the imported pelvis
and chest rotations are never replaced with identity rotations. This keeps the
model upright and lets the idle pose lower both arms from the source T-pose.

These overlays are still authored procedural poses, not full retargeted motion
clips. The next quality step remains baking reviewed HumanML3D or motion-library
clips onto the imported Jue skeleton.

## Runtime Q-character binding

Converted Q characters can now join the shared motion/expression libraries and
the LLM story cast without adding a model-specific branch to StoryDirector:

1. Convert the source character to a Godot-readable GLB with its skeleton,
   material textures and blend shapes preserved.
2. Create a version-1 character manifest based on
   `data/examples/chibi_character_manifest.example.json`.
3. Attach `character_runtime_binding.gd` to the character scene and point
   `manifest_path` at that manifest.
4. Keep `CharacterAnimationDriver` and `CharacterExpressionDriver` under the
   Agent node. They consume the registered `clip_map` and `channel_map`.
5. Place the CharacterBody3D in the `agents` group through `agent_base.gd`.

At runtime the manifest adds the new `agent_id` to
`CharacterAdapterRegistry`. The ECNU planning prompt then includes its display
name, identity and available shared actions. StoryDirector already resolves any
registered cast member from the `agents` group, so the same generated Story
beats can drive the new character.

The semantic contract is shared; the physical assets remain model-specific:

```text
ECNU / motion router emits: wave + happy
Character adapter maps:     wave -> Wave_01, joy -> Fcl_MTH_Smile
Animation/expression driver: plays this Q model's clip and morph
```

PMX itself is not a runtime format. A PMX archive cannot use this binding until
it has been converted and inspected. Animation clips also cannot be copied
blindly between different rest poses; each skeleton family needs a reviewed
retarget/bake, after which all characters continue to use the same action IDs.

### Local-only MMD packages (`v0.8.5`)

Models whose licenses prohibit redistribution must never appear as a direct
`ext_resource` in a published scene. The living room now contains
`LocalCharacterSpawner`, which checks ignored manifests under
`assets/local_characters/` and skips them when absent. Each available package is
instantiated from `local_runtime_character.tscn`, registered with the same
adapter registry, and receives an independent Agent ID and memory partition.

The local validation catalog currently contains:

- Castorice / 遐蝶 (`castorice_agent`): 272 bones, 37 morphs;
- Cartethyia / 卡提希娅 (`cartethyia_agent`): 652 bones, 69 morphs;
- Xiangli Yao / 相里要 (`xiangliyao_agent`): 495 bones, 70 morphs.

All three packages use the same runtime contract:

- PMX converted by `tools/blender/export_local_mmd_character.py`;
- MMD node groups rebuilt as portable Principled texture materials;
- original skeletons and morphs preserved;
- Japanese MMD bones mapped to semantic body bones;
- `笑い/怒り/まばたき/あいうえお` mapped to shared expression channels;
- dynamic `@显示名` routing, StoryDirector cast registration and independent
  story memory verified for every actor;
- a generated multi-role story can target all available local actors without
  hard-coding their model skeletons in StoryDirector.

`v0.8.7` upgrades that contract to a distance-driven semantic `walk` overlay. Movement
still comes from the navigation controller, while mapped MMD hip, upper/lower leg,
foot and arm bones provide visible gait. A blocked actor freezes its gait phase and
blends back toward rest instead of walking in place. The three local profiles use
slightly different stride and swing values rather than one identical cycle. The expression
adapter also maps shared `sad`, `surprised`, `shy`, `bored` and `confused`
channels to each model's native Japanese morph names. These channels are
validated against the live meshes, not merely accepted as configuration.

The live ECNU acceptance now derives required cast members from every registered
display name mentioned in the player's script. A five-character test using
咕咕嘎嘎、诀、卡提希娅、相里要 and 遐蝶 produced and executed 16 beats with
movement, object interaction, dialogue, expressions and per-character memory.

The converted GLB and its manifest are ignored by Git. Open-source checkouts
therefore run with the built-in characters only, while an authorized local
installation can add multiple manifests without editing StoryDirector.

## Next real motion step

To truly use the offline motion library across models:

1. Normalize shared action ids (`wave`, `nod`, `walk`, etc.).
2. For each model, define a skeleton map and rest-pose correction.
3. Bake each action id into character-specific animation clips.
4. Export those clips into Godot as `AnimationPlayer` animations.
5. Keep the LLM/router layer unchanged.

The current local catalog has one generated `smoke_walk` fixture/package plus dataset
statistics (`Mean.npy` and `Std.npy`), but no reviewed real HumanML3D corpus clip baked
for every skeleton. Therefore Jue/Q `walk/wave/nod/think/happy/talk` currently use
reviewed semantic bone overlays; richer full-body clips still require real
`.npy`/BVH/VMD source motion, offline retargeting and baking.

| Character family | Current walk backend | Status |
|---|---|---|
| 咕咕嘎嘎 | Native `AnimationPlayer` `walk` | Production baseline |
| 诀 | Distance-driven semantic leg overlay | Temporary until retarget bake |
| Local MMD Q cast | Per-character distance-driven gait profiles | Local reviewed baseline |
| HumanML3D `smoke_walk` | Offline fixture/package | Pipeline smoke test, not a corpus |

This keeps intelligence and asset adaptation separate:

```text
LLM/router chooses "wave"
咕咕嘎嘎 adapter plays penguin wave clip
诀 adapter plays Jue-retargeted wave clip
```

## Anime rendering profile (`v0.8.11`)

All materialized character families now share `anime_toon_v1` without changing
their skeleton or motion adapter. `AnimeRenderAdapter` walks only the declared
model subtree, duplicates each live `StandardMaterial3D`, preserves its color and
textures, then enables Godot's Toon diffuse/specular response.

Each surface receives a second-pass outline shader. The shader:

- expands back faces along their normals and draws a dark purple silhouette;
- samples the source albedo alpha, so hair cards and cut-out clothing do not
  become solid blocks;
- divides the local outline width by model scale, keeping Jue's centimeter-scale
  FBX and the Q models visually consistent.

The adapter is attached to `main_agent.tscn`, `jue_agent.tscn` and
`local_runtime_character.tscn`; newly imported manifest characters therefore
inherit the same style automatically. Furniture and room meshes are outside those
model roots and remain PBR.

Validate the live material boundary with:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/anime_character_rendering_check.gd
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

Runtime Q-character manifest registration is covered separately:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/chibi_runtime_binding_check.gd
```

Optional local PMX conversion and runtime coverage:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/local_character_import_check.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/local_character_runtime_check.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/local_character_catalog_check.gd
```

Locomotion synchronization and gait quality:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/locomotion_quality_check.gd
```
