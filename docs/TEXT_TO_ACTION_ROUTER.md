# Text-to-action router

This demo now uses a lightweight retrieval-first architecture for mapping player
language to character performance:

1. The LLM reads the player message and emits structured intent, including
   `goal`, `emotion`, `gesture`, `plan`, and an optional short `motion_query`.
2. `motion_query` is treated as the semantic search query for the motion library.
   If the LLM omits it, the original player message is used.
3. `MotionIntentRouter` first checks high-precision catalog rules for scene goals
   such as `watch_tv`, `patrol_room`, and `read_book`.
4. If no exact rule matches, it loads `data/router_model.json` and retrieves the
   closest action prototype.
5. The selected `action_id` maps to the existing Godot animation clip and the
   selected expression maps to the expression driver.

Expression now has a parallel retrieval path documented in
`docs/EXPRESSION_ROUTER.md`. The key difference is that motion chooses a baked clip,
while expression can blend multiple morph targets continuously.

The current local artifact is intentionally tiny:

- Feature provider: `hash_char_ngram_v1`
- Dimensions: 1024
- Model type: centroid/prototype router
- Training source: generated examples from `data/motion_catalog.json`,
  `data/expression_catalog.json`, and `motion_lab/router_training/seed_intents.jsonl`

This is not a replacement for Light-T2M. It is the fast real-time layer that chooses
among baked clips. Light-T2M or HumanML3D remains the offline source for generating
or baking more clips into the library.

## Local training

```bash
python3 motion_lab/router_training/scripts/build_training_data.py
python3 motion_lab/router_training/scripts/train_router.py --provider hash
```

The exported runtime artifact is:

```text
data/router_model.json
```

## ECNU embedding experiment

For a true semantic embedding experiment, set the API key outside Git and train:

```bash
export ECNU_EMBEDDING_API_KEY="..."
python3 motion_lab/router_training/scripts/train_router.py --provider ecnu
```

The ECNU model exports the same centroid contract, but Godot currently only runs
the local hash provider directly. For production, either:

- call the ECNU embedding endpoint from a small local backend and return the chosen
  `action_id`, or
- precompute a richer action library and use the LLM to emit canonical `motion_query`
  values that the local router can match safely.

Do not commit API keys or private conversation logs.
