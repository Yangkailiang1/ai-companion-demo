# Expression router

The expression system now mirrors the text-to-action router, but uses continuous
morph blending instead of choosing exactly one animation clip.

Runtime flow:

```text
Player message / LLM response
  -> expression_query
  -> ExpressionIntentRouter
  -> expression payload: { expression, morph_weights, fade_duration, hold_seconds }
  -> MessageBus.expression_blend_cue
  -> CharacterExpressionDriver
  -> penguin blend shapes
```

The library lives in:

```text
data/expression_library.json
```

Each entry contains:

- `description` and `aliases` for retrieval;
- `morph_weights`, mapped to the current penguin blend shapes;
- optional `bone_fallback` metadata for future head/eye pose support;
- `fade_duration` and `hold_seconds` for timing.

The current penguin exposes only a small morph set (`joy`, `angry`, `blink`, and
mouth vowels such as `a/i/u/e/o`), so richer expressions like `shy_happy` and
`confused` are approximations. A future VRM/ARKit-style model can reuse the same
library structure with a wider morph map.

## LLM contract

`CognitiveCycle` asks the LLM to emit:

```json
{
  "emotion": "happy",
  "emotion_intensity": 0.7,
  "expression_query": "害羞但开心地笑"
}
```

If `expression_query` is missing, the router falls back to the player message,
speech text, and finally the simple `emotion` label.

## Why expression differs from motion

Motion is usually discrete: choose `wave`, `walk`, `nod`, etc.

Expression is better as continuous blending:

```text
shy_happy ≈ joy 0.62 + blink 0.16 + mouth a 0.05
```

This allows subtle expression changes without needing a separate baked animation for
every emotional nuance.
