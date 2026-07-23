# Autonomous life runtime

## Current Utility AI slice

Autonomous life is selected from a data-driven activity catalog:

```text
environment + per-Agent needs + distance + personality preference
  -> score every available Agent/activity pair
  -> reject cooldowns, busy Agents and reserved resources
  -> select the highest score above its threshold
  -> orient to the target, then expand safe GOAP actions
  -> execute, apply effects to that Agent, release resources
  -> write outcome to that Agent's memory
```

The initial catalog in `data/autonomous_life_config.json` contains plant care,
reading, sofa rest and room wandering. 咕咕嘎嘎 prefers plant care and movement;
诀 strongly prefers reading. Plant dryness remains a high-priority condition, but
it now competes through the same inspectable scoring pipeline.

Candidate scores currently combine:

```text
(base + need deficit + condition urgency + distance bonus) × personality preference
```

The runtime stores the complete candidate list and selected score in
`AutonomousBehaviorSystem.get_diagnostics()`. The LLM may propose high-level goals
and natural dialogue, but it does not produce coordinates, bypass navigation, or
directly rotate bones.

## Priority and interruption

Only an idle Agent can accept an autonomous activity. Activities have individual
cooldowns and a short post-activity quiet period. Multiple Agents may act at once
when their resources do not conflict. Book, sofa and plant reservations prevent
two Agents from claiming the same interaction.

Player input has higher priority: `MessageBus.player_message_received` immediately
cancels active autonomous queues, releases reservations, records the interruption,
and leaves `CognitiveCycle` free to generate the player's response.

Automatic dialogue uses normal bubbles, chat history, TTS requests, and
performance cues. It does not emit `agent_spoke`, preventing two social listeners
from recursively replying forever.

## Multi-Agent behavior

World needs are stored per `agent_id`. Reading by 诀 therefore restores 诀's fun,
not 咕咕嘎嘎's. The acting Agent records both its intention and completed
experience. An idle companion may observe plant care, store a separate episode,
and update its relationship toward the actor.

When every formal activity is unavailable or cooling down, the scheduler can
produce a silent contextual micro behavior such as looking toward a preferred
object or thinking. These cues are personality-configured and cooldown-limited,
so they do not generate chat spam.

## Adding the next autonomous activity

1. Expose structured state and affordances through `SemanticWorld`.
2. Add safe GOAP blueprints or validated primitive actions.
3. Add a policy precondition, cooldown, priority, and completion condition.
4. Store outcomes by `agent_id`, not in shared prose memory.
5. Add a headless acceptance check covering real navigation and state mutation.

The next scoring inputs are schedule fit, relationship context, activity duration
and explicit task resumption after a player interruption.

## Validation

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/autonomous_life_check.gd
```

The test verifies the orientation transition plus five-action routine, real plant
moisture change, arrival at the sofa interaction point, separated memories,
relationship change, and player interruption.

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/utility_life_check.gd
```

The Utility AI test verifies personality-based reading selection, orientation,
resource reservation/release, per-Agent need effects, outcome memory, concurrent
non-conflicting selection, diagnostics and silent micro behavior.
