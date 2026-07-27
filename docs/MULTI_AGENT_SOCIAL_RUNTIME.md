# Multi-agent social runtime

The living room now contains two agents:

- `main_agent` — 咕咕嘎嘎, the original penguin companion.
- `jue_agent` — 诀；本机可从 Git 忽略目录加载人形 FBX，公开检出使用占位外观。

Both agents use the same high-level runtime contracts:

```text
LLM / local fallback
  -> motion_query / expression_query
  -> action router / expression router
  -> targeted performance and expression cues
  -> AgentBase movement and driver playback
```

## Targeted cues

`performance_cue`, `expression_cue`, `expression_blend_cue`, and world-space speech
bubbles now carry or respect `agent_id` in their context. This prevents a command for
one agent from accidentally making every character wave, blink, or speak.

## Independent memory

`MemorySystem` now stores memories by `agent_id` while keeping the old single-agent
API as a compatibility wrapper for `main_agent`.

Useful APIs:

```gdscript
MemorySystem.add_episode_for_agent("jue_agent", "玩家夸奖了诀", 5.0)
MemorySystem.format_for_llm_for_agent("jue_agent", "玩家刚才说的话")
MemorySystem.update_relationship_for_agent("jue_agent", "main_agent", "familiarity", 0.05)
```

## Player targeting

Player messages default to 咕咕嘎嘎. To address 诀, prefix the input:

```text
诀，挥挥手
@诀 一起去看电视吗
```

## Lightweight social behavior

`SocialSystem` listens when an agent speaks:

1. Other agents record the line in their own memory.
2. Their relationship familiarity with the speaker increases slightly.
3. With a conservative cooldown/probability gate, an idle listener may respond.

This is intentionally restrained so the two agents do not endlessly ping-pong.

## Current limitation

`诀` imports successfully as FBX with meshes and morph targets, but no AnimationPlayer
clips are present in the imported scene. For now she uses procedural fallback
gestures (`wave`, `nod`, `think`, `happy`, `talk`) and AgentBase locomotion. The next
deeper animation step is to retarget baked HumanML3D/motion-library clips to her
skeleton or export a GLB with named animation clips from a stable Blender/MMD pipeline.

See `docs/CHARACTER_ADAPTERS.md` for the shared-library plus per-character-adapter
plan.
