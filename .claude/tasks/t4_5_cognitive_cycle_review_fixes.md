# Review fixes: T4.5 CognitiveCycle split

Work in `/Users/yangkailiang/Documents/ai_games/ai_companion_demo`.

The first split is directionally good, but Codex review rejected it pending the
issues below. Read root `CLAUDE.md` and the exact roadmap node files before editing.
Do not commit or touch unrelated user files.

## 1. Fix roadmap traceability

- `X3.1` does not exist. Use `X3`.
- `C1.1` specifically means route logging/dataset, which these helpers do not
  implement. Use parent `C1` for general text/action routing.
- Use `T1` for general cognition protocol. Use `T1.1` only where the function
  actually implements the unified PerformanceIntent work.
- Suggested file ownership:
  - `cognitive_cycle.gd`: `T1, X3, T4.5`
  - `prompt_builder.gd`: `T1, X3, T4.5`
  - `performance_resolver.gd`: `C1, C3, T4.5`
  - `local_fallback_decider.gd`: `T1, C1, X3`
- Every function, including `_sanitize_expression()` and `_empty_performance()`,
  needs an immediately preceding roadmap comment.

## 2. Restore exact fallback trigger behavior

The old SIMULATION branch checked `current_trigger.data.need_type`:

- only a HUNGER trigger could choose hunger fallback;
- only a FUN trigger could choose bored/watch-TV fallback;
- otherwise codified reaction was used.

The extracted decider currently ignores `need_type` and selects hunger whenever
hunger is low, even during a FUN trigger. This is a behavior regression.

Pass the trigger data or explicit need type into `LocalFallbackDecider.decide()`
and restore the old branch semantics exactly.

## 3. Restore router-derived explicit prompt constraints

Before the split, `_build_explicit_player_instruction()` called
`_infer_explicit_player_goal()`, which consulted the motion router before keyword
fallback. Therefore catalog intent `"过来"` constrained the LLM prompt to goal
`come_here`.

The new PromptBuilder only checks hard-coded keywords, so `"过来"` is no longer
constrained. Restore this behavior without making PromptBuilder own scene state:

- CognitiveCycle/PerformanceResolver may derive the explicit routed goal;
- pass the resolved explicit goal/instruction into the pure PromptBuilder;
- preserve public `CognitiveCycle.build_prompt(...)`.

Add a headless contract assertion that a prompt built for `"过来"` contains the
explicit `come_here` goal constraint.

## 4. Enforce function size

`LocalFallbackDecider.decide()` is far beyond the 60-line hard limit. Split it
into cohesive pure helpers, for example:

- base/default decision;
- player-input decision;
- actionable routed decision;
- simulation decision;
- idle decision.

Keep the file under 300 lines and 20 functions. Every helper needs a real roadmap
comment. Also reduce any modified function over 60 lines where practical,
especially `_handle_decision()` and `_use_local_fallback()`, without producing
meaningless forwarding files.

## 5. Restore strong enum types

Try restoring `AffordanceTypes.TriggerSource` for the public CognitiveCycle
signatures and helper signatures. The original file compiled with this enum.
Do not accept `int` merely on speculation. If a real parse error occurs, capture
the exact Godot error and use `int` only at the isolated helper boundary.

## 6. Side-effect ownership

The `performance_resolver.gd` header says CognitiveCycle retains all signal
emission, but `emit_expression_performance()` emits MessageBus signals. Either:

- move emission back to the orchestrator / a clearly named emitter; or
- correct the responsibility statement so it truthfully owns expression cue
  emission.

Do not claim a class is pure if it emits signals.

## Validation

Run at least:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/headless_check.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/gesture_pipeline_check.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/multi_agent_check.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/agent_psyche_check.gd
```

Add/run a focused contract test covering:

1. router-only explicit goal `"过来"` appears as `come_here` in prompt;
2. FUN simulation trigger does not choose hunger fallback merely because hunger
   is low;
3. HUNGER simulation trigger still chooses the hunger fallback when hunger is low.

Run `git diff --check`. Report final lines/functions and the exact tests.
