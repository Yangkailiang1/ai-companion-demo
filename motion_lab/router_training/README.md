# Lightweight router training package

The current game uses a deterministic catalog router plus the existing LLM's
structured `gesture` and `emotion` fields. If a dedicated router is later required,
train it here as a small multi-task classifier rather than retraining Light-T2M.

Recommended outputs:

- `action_id`: one of the catalog actions or `generated_motion`
- `expression`: one of the expression catalog entries
- `motion_request`: whether the player explicitly requested physical movement
- `confidence`: calibrated probability used to retain the safe library fallback

Keep raw/private conversations outside Git. `seed_intents.jsonl` is only a schema and
smoke-test seed; it is not sufficient training data. A useful first dataset should
contain negations, questions, compound instructions, Chinese/English variants, and
hard negatives. Export the trained artifact to `motion_lab/checkpoints/router/`, which
is ignored by Git.
