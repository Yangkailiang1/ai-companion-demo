# Autonomous life runtime

## Current vertical slice

The first environment-driven routine is implemented as a bounded runtime policy:

```text
PlantState reports dry
  -> SemanticWorld publishes the changed object state
  -> AutonomousBehaviorSystem checks priority and cooldown
  -> GOAPPlanner expands water_plant + rest_on_sofa
  -> AgentBase / ActionExecutor navigate, water, navigate, sit, rest
  -> PlantState changes moisture
  -> each observing Agent writes its own episode/relationship memory
```

This policy is deliberately deterministic. The LLM may propose goals and natural
dialogue, but it does not produce coordinates, bypass collision/navigation, or
directly rotate bones. This keeps physical behavior reproducible and testable.

## Priority and interruption

Only an idle Agent can accept an autonomous routine. One routine may own an Agent
at a time, and the same routine has a 45-second cooldown. Player input has higher
priority: `MessageBus.player_message_received` immediately cancels the autonomous
action queue, then `CognitiveCycle` can generate the player's response.

Automatic dialogue uses normal bubbles, chat history, TTS requests, and
performance cues. It does not emit `agent_spoke`, preventing two social listeners
from recursively replying forever.

## Multi-Agent behavior

The acting Agent records both its intention and the completed experience. An idle
companion may acknowledge the action, store an episode under its own `agent_id`,
and update its relationship toward the actor. This is the minimum social
observation loop; it is not yet a general multi-Agent conversation planner.

## Adding the next autonomous activity

1. Expose structured state and affordances through `SemanticWorld`.
2. Add safe GOAP blueprints or validated primitive actions.
3. Add a policy precondition, cooldown, priority, and completion condition.
4. Store outcomes by `agent_id`, not in shared prose memory.
5. Add a headless acceptance check covering real navigation and state mutation.

Future policies should move from hard-coded checks to data-driven utility scoring:
`urgency × personality preference × distance × schedule fit × social context`,
while keeping execution constrained by affordances and navigation.

## Validation

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/autonomous_life_check.gd
```

The test verifies the five-action routine, real plant moisture change, arrival at
the sofa interaction point, separated memories, relationship change, and player
interruption.
