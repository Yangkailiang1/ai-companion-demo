# O2.2 Character Intake Schema — bounded implementation

Read `CLAUDE.md`, `docs/ASSET_PIPELINE_CONTRACTS.md`,
`.claude/skills/prepare-character-model-assets/SKILL.md`, and the existing
`assets/characters/penguin/*.json` metadata before editing.

Implement only the first O2.2 machine-readable intake slice. Do not modify Godot
runtime, scenes, models, existing metadata, roadmap/docs, Git, or ignored
`assets/local_characters/`.

## Allowed output files

1. `data/asset_pipeline/schemas/character_intake.schema.json`
2. `assets/characters/penguin/character_intake.json`
3. `tools/assets/validate_character_intake.py`
4. `tools/assets/test_validate_character_intake.py`

Do not create or modify any other file.

## Contract

The schema must use JSON Schema draft 2020-12 and reject unknown fields. Required:

- `schema_version`: exactly `1`
- `character_id`: stable lower snake_case
- `classification`: one of `public_redistributable`, `local_only`, `rejected`
- `status`: one of `downloaded`, `inventoried`, `metadata_candidate`,
  `quarantined`, `rejected`; never `accepted`
- `model_path`, `provenance_path`: `res://` paths
- `inventories`: object with required `bones`, `morphs`, `animations`, each a
  `res://` JSON path
- `source_sha256`: lowercase 64-hex
- `notes`: optional array of non-empty strings

Cross-field rules enforced by the dependency-free CLI:

- all referenced `res://` files must exist under `--project-root`, without path
  traversal or absolute machine paths;
- referenced JSON must parse;
- `source_sha256` must equal the referenced provenance `source_sha256`;
- `classification=public_redistributable` requires provenance
  `redistribution=allowed` and a non-empty, non-`unknown` license;
- `classification=local_only` requires provenance
  `redistribution=local_only`;
- `classification=rejected` requires `status=rejected`;
- all other classifications must not use `status=rejected`.

The CLI accepts one or more intake files plus optional `--project-root`. It exits
0 only if all pass and prints a compact `CHARACTER_INTAKE_PASS` line; otherwise
non-zero with actionable stderr. Use only Python standard library.

The penguin intake must reflect facts already present in its provenance:
`classification=local_only`, not accepted, and reference the existing model and
three inventories.

Tests must use `tempfile` fixtures and cover at least:

1. valid local-only package;
2. valid public package;
3. unknown license rejected for public;
4. redistribution mismatch;
5. SHA mismatch;
6. missing referenced file;
7. path traversal / machine path;
8. rejected cross-field rule;
9. real penguin intake passes.

Keep each Python file within CLAUDE.md limits; target the test at <=220 lines.
Every function docstring must include `[O2.2]` and side effects. Do not weaken
assertions by conditionally skipping malformed required fields.

## Required validation

```bash
python3 -m py_compile \
  tools/assets/validate_character_intake.py \
  tools/assets/test_validate_character_intake.py
python3 -m unittest tools.assets.test_validate_character_intake -v
python3 tools/assets/validate_character_intake.py \
  assets/characters/penguin/character_intake.json \
  --project-root .
wc -l tools/assets/validate_character_intake.py \
  tools/assets/test_validate_character_intake.py
git diff --check
```

Return changed files, command results, and any contract ambiguity. Do not claim
visual/runtime acceptance.
