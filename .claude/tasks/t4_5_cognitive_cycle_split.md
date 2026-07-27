# Task: T4.5 / T1 / C1 — split CognitiveCycle without behavior changes

Work in `/Users/yangkailiang/Documents/ai_games/ai_companion_demo`.

Read before editing:

- `CLAUDE.md`, especially “Claude / Codex 强制工程规范”
- `docs/roadmap/T-runtime/T1-cognition-action-protocol.md`
- `docs/roadmap/T-runtime/T4-engineering-foundation.md`
- `docs/roadmap/C-characters/C1-text-to-action-routing.md`
- `scripts/core/cognitive_cycle.gd`
- existing headless tests under `scripts/debug/`

## Objective

Refactor the oversized `scripts/core/cognitive_cycle.gd` Autoload into cohesive,
testable project-owned modules. Preserve all externally visible behavior,
autoload name, public compatibility points, signals and fallback responses.

This is a structural refactor only. Do not add product features or change prompts,
gesture selection, expression selection, GOAP goals, dialogue text, queue ordering,
network configuration behavior or save data.

## Required outcome

1. Reduce `cognitive_cycle.gd` from 767 lines to at most 500 lines; target 350–450.
2. Extract at least two genuinely cohesive responsibilities. Good candidates:
   - prompt construction;
   - provider request envelope / response decoding;
   - local fallback policy;
   - decision-to-performance resolution.
3. Each extracted GDScript file must remain at most 300 lines and 20 functions.
4. Do not add new Autoloads. `CognitiveCycle` remains the orchestration facade.
5. Preserve these compatibility points:
   - `CognitiveCycle.build_prompt(...)`;
   - public `llm_api_url`, `llm_api_key`, `llm_model`, `llm_provider`;
   - `is_processing` and player-trigger FIFO behavior;
   - existing `MessageBus` signal payloads;
   - local fallback output used by gesture and multi-Agent tests.
6. Pure helpers should extend `RefCounted` where possible. They must not mutate
   scene nodes, positions, memories or UI.
7. Add file headers and immediately preceding function comments required by
   root `CLAUDE.md`. Use real roadmap IDs such as `T1.1`, `C1.1`, `C3.1`,
   `X3.1`, `T4.5`; no invented IDs.
8. Use typed public functions and explicit `-> void`.
9. Do not modify or stage unrelated user files. In particular leave these alone:
   - `.claude/tasks/v04_download_offline_gpu_assets.md`
   - `docs/CLAUDE_DOWNLOAD_HANDOFF.md`
   - `scripts/debug/xiaoguang_bounds_dump.gd.uid`
   - research PDFs, model assets and scene archives
10. Do not commit or push. Codex will review and commit after acceptance.

## Design guidance

- Keep cross-domain side effects in `CognitiveCycle`; extracted components should
  return structured dictionaries/strings.
- Do not make UI, providers or routers authoritative over physical execution.
- Avoid a “helper” that merely moves the same 300-line monolith unchanged.
- Prefer dependency injection of the existing motion/expression routers over
  accessing Autoload private fields.
- Do not duplicate constants across files unless one module clearly owns them.
- Maintain the current public prompt facade even if construction moves to a helper.

## Validation

At minimum run:

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

Also run `git diff --check` and report:

- files created/changed;
- final line/function counts;
- tests executed and results;
- any compatibility concern left for Codex review.
