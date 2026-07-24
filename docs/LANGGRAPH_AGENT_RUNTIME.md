# LangGraph-compatible character cognition

## Decision

Each character should be a separate **state instance**, not a separately authored
graph. The recommended production shape is:

```text
one shared compiled cognition graph
  + thread_id = "agent:<agent_id>"
  + per-Agent profile / psyche / memory namespaces
  + optional specialist subgraphs
```

This follows LangGraph's persistence model: checkpoints are organized by
`thread_id`, while long-term memory can use separate store namespaces. Stateful
subgraphs require stable names to avoid checkpoint namespace collisions.

Official references:

- https://docs.langchain.com/oss/python/langgraph/persistence
- https://docs.langchain.com/oss/python/langgraph/use-subgraphs
- https://docs.langchain.com/oss/python/langgraph/add-memory

## Why LangGraph is not the physics controller

The graph is appropriate for slow cognition:

```text
perceive
  -> retrieve short/long memory
  -> update psyche and beliefs
  -> reflect when needed
  -> propose goals
  -> arbitrate plan
  -> produce dialogue/performance intent
```

Godot remains authoritative for:

- Utility scoring and immediate reactions;
- collision, navigation and reachability;
- object reservations and ownership;
- GOAP primitive validation;
- animation, IK, audio and scene state mutation.

The LLM/LangGraph layer may propose `goal`, `target_id`, dialogue and expressive
intent. It may not output trusted coordinates, mutate nodes directly or bypass
affordances. This preserves responsiveness and prevents prompt injection from
becoming physical game authority.

## Per-character instantiation

The graph topology is shared. Character creation injects:

- identity and speech style;
- OCEAN traits and motives;
- baseline mood and emotion decay;
- activity preferences and cooldowns;
- memory namespace and initial memories;
- relationship/belief state;
- voice, expression and skeleton adapter IDs.

Current examples live in:

- `data/character_config.json`
- `data/agent_psychology.json`
- `data/autonomous_life_config.json`
- `data/character_runtime_adapters.json`

## State contract

`AgentPsycheSystem.build_graph_state(agent_id, trigger)` produces the initial
contract described by `data/cognitive_graph_state.schema.json`.

Important channels:

| Channel | Purpose |
|---|---|
| `thread_id` | Checkpoint isolation for one character |
| `profile` | Stable identity, OCEAN traits and motives |
| `psyche` | Mood, attention, intention, beliefs and recent activity |
| `daily_plan` | Current day/period priorities and completed activities |
| `world` | Current semantic perception, never raw scene-tree authority |
| `memory_context` | Retrieved context, not the complete unbounded history |
| `reflection` | Bounded reflection candidate awaiting memory write |
| `candidate_goals` | Proposals awaiting deterministic validation |
| `selected_goal` | Arbitrated high-level goal |
| `response` | Dialogue and performance intent returned to Godot |

Suggested persistent namespaces:

```text
("agent", agent_id, "biography")
("agent", agent_id, "relationships")
("agent", agent_id, "reflections")
("shared_world", save_id, "facts")
```

## Runtime graph

The local prototype now compiles one reusable graph:

```text
START
  -> perceive
  -> retrieve_memory
  -> update_psyche
  -> reflect_if_needed
  -> propose_goals
  -> validate_and_arbitrate
  -> compose_response
  -> END
```

Social inference can be a named subgraph with its own schema. It should update
beliefs as uncertain observations rather than writing another character's private
state as fact.

`reflect_if_needed` currently supplies a deterministic baseline: a reflection
trigger summarizes recent activity and mood, while normal turns pass through
without inventing a reflection. Daily-plan priorities add a bounded bonus during
goal proposal. Godot still validates conditions, reservations and execution.

## Integration phases

1. **Current:** Godot owns the compatible state schema and psychological runtime.
2. Add a local Python LangGraph process used only for player dialogue/reflection.
3. Add SQLite checkpointing keyed by `thread_id`; keep saves portable.
4. Move daily/long-term planning into the graph after deterministic validation.
5. Keep an offline Godot fallback so the game remains playable without Python,
   network access or an LLM provider.

Do not run one Python service per character. One process can execute the shared
graph concurrently with isolated thread/checkpoint state.

## Validation

```bash
python3 cognition_lab/smoke_test.py
```

Expected:

```text
LANGGRAPH_AGENT_PASS main=water_plant jue=read_book reflection=read_book threads=isolated
```

Godot-side psyche, attention, prompt and save integration:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/agent_psyche_check.gd
```
