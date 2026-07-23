# Lightweight text-to-action router package

The current game uses a retrieval-first router plus the existing LLM's structured
`goal`, `gesture`, `emotion`, `plan`, and `motion_query` fields.

Recommended runtime architecture:

1. LLM extracts a short `motion_query`, for example `开心地挥手问候`.
2. The router compares that query with the motion/action library.
3. The selected `action_id` maps to a baked Godot animation clip.
4. Expression is selected separately and sent to the expression driver.

This is intentionally lighter than retraining Light-T2M. Light-T2M/HumanML3D should
be treated as an offline source for adding more baked clips to the library.

Recommended outputs:

- `action_id`: one of the catalog actions or `generated_motion`
- `expression`: one of the expression catalog entries
- `motion_request`: whether the player explicitly requested physical movement
- `confidence`: calibrated probability used to retain the safe library fallback

Local smoke training:

```bash
python3 motion_lab/router_training/scripts/build_training_data.py
python3 motion_lab/router_training/scripts/train_router.py --provider hash
```

ECNU embedding experiment:

```bash
export ECNU_EMBEDDING_API_KEY="..."
python3 motion_lab/router_training/scripts/train_router.py --provider ecnu
```

Keep raw/private conversations outside Git. `seed_intents.jsonl` is only a schema and
smoke-test seed; it is not sufficient training data. A useful first dataset should
contain negations, questions, compound instructions, Chinese/English variants, and
hard negatives.
