# v0.4 — Light-T2M Motion/Expression Bridge

You are implementing a bounded bottom-layer feature inside this Godot 4.6.1 project.
Do not read or modify `data/.env` or `data/llm_config.json`. Do not use network access,
download dependencies, modify binary assets, or commit/push Git changes.

## Goal

Add a deterministic, testable bridge from player text to an action-library clip and
facial expression. Leave a clean provider interface for a future Light-T2M server.
Light-T2M inference and training do not run inside Godot.

Data flow:

`text -> MotionIntentRouter -> MotionDecision -> performance_cue + expression_cue`

Unknown/generative motions must return provider `light_t2m` plus a safe library
fallback. Existing movement/GOAP behavior must remain unchanged.

## Known character capabilities

- Existing animation clips: `idle`, `walk`, `wave`, `nod`, `think`, `happy`, `sit`.
- 64-bone GLB includes body bones: `root`, `hips`, `spine`, `chest`, `neck`, `head`,
  `shoulder.L/R`, `upper_arm.L/R`, `lower_arm.L/R`, `hand.L/R`, `upper_leg.L/R`,
  `lower_leg.L/R`, `foot.L/R`, `toes.L/R`, `eye.L/R`.
- Morph targets include `blink`, `blink_l`, `blink_r`, `blink.l`, `blink.r`, `joy`,
  `angry`, and visemes `a/i/u/e/o` across several meshes.

## Required implementation

1. Add `data/motion_catalog.json` with library actions, Chinese/English keyword aliases,
   clip name, loop flag, default duration, tags, and Light-T2M prompt template.
2. Add `data/expression_catalog.json` mapping at least neutral/happy/angry/sad/
   surprised/excited/bored/blink/talk to morph weights and optional head/eye fallback.
3. Add `data/humanml3d_penguin_bone_map.json` defining canonical HumanML3D 22-joint
   names and target penguin bone names. Mark intentionally approximated joints.
4. Add `scripts/characters/motion_intent_router.gd` (`class_name MotionIntentRouter`).
   It must load catalogs, normalize Chinese/English text, score aliases/tags, and return
   a Dictionary with: action_id, clip, expression, confidence, provider, fallback_clip,
   style, speed, duration, source_text, generation_prompt. It must be deterministic.
   Known library motions use provider `library`; unknown physical requests use
   `light_t2m` with a safe fallback. Ordinary conversation should use `talk`/`idle`,
   not generate arbitrary motion.
5. Add `scripts/characters/expression_driver.gd`. Listen to a new MessageBus signal
   `expression_cue(expression: String, intensity: float, context: Dictionary)`.
   Recursively discover MeshInstance3D nodes, resolve blend shape indices by name,
   cross-fade weights, tolerate missing targets, and support blink/talk viseme hooks.
   No hard-coded imported node paths.
6. Add the ExpressionDriver node beside CharacterAnimationDriver in the living-room
   agent scene.
7. Integrate routing in CognitiveCycle for PLAYER_INPUT only. Explicit GOAP spatial
   goals remain authoritative. Library motion/expression may refine the current cue;
   no new HTTP request and no blocking. Emit expression cue with emotion intensity.
8. Extend the LLM JSON schema/prompt only as needed; preserve backwards compatibility.
9. Add `scripts/debug/motion_expression_bridge_check.gd` covering at least 12 Chinese/
   English prompts, including known actions, conversation, emotion, and one unknown
   physical action routed to Light-T2M fallback. Verify 22 joint mappings target known
   penguin bones and expression catalog structure.
10. Add `docs/LIGHT_T2M_INTEGRATION.md` documenting that official Light-T2M is a
    CUDA/PyTorch server/offline provider, while Godot uses the deterministic library
    router in real time.
11. Add `motion_lab/` scaffolding for later server training/deployment:
    `README.md`, `requirements-server.txt`, `configs/`, `scripts/`, `datasets/README.md`,
    `checkpoints/README.md`, `generated/README.md`. Datasets, checkpoints, generated
    binary motions, virtualenvs, and vendored upstream code must be ignored. Include a
    JSON-lines contract/example for request and output metadata, but do not invent a
    fake neural implementation.

## Quality constraints

- GDScript must parse in Godot 4.6.1.
- Do not remove or rename existing signals/clips/tests.
- Do not let expression cues interrupt locomotion.
- Do not claim actual Light-T2M inference occurred.
- Use tabs for GDScript indentation, UTF-8 JSON, and concise comments.
- Run existing headless, gesture, spatial tests plus the new bridge test using the
  absolute Godot app path and `--log-file /tmp/...`.

Report changed files, commands run, and remaining limitations when finished.
