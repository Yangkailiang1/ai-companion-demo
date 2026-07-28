# Expression package contract

## Accepted inputs

| Input | Role |
|---|---|
| GLB/GLTF morph targets | Preferred runtime facial channels |
| VRM preset/custom expressions | Semantic mapping source after importer/conversion review |
| FBX blend shapes | Offline conversion and inventory |
| PMX/MMD morphs | Local-only conversion unless redistribution is explicitly allowed |
| facial VMD | Optional time curves; separate from body tracks |
| facial bones | Safe fallback for head/eyes/brows when morphs are absent |

## Shared semantic layer

The shared library may contain:

```text
neutral, joy, angry, sad, surprised, shy, bored, confused,
blink, a, i, u, e, o
```

It stores descriptions, bilingual aliases, semantic weights, fade duration, hold
duration, and approximation metadata. It never stores concrete mesh channel names.

## Per-character adapter

```json
{
  "type": "blend_shapes",
  "channel_map": {
    "joy": ["native_smile", "笑い"],
    "blink": ["Blink", "まばたき"],
    "a": ["A", "あ"]
  }
}
```

Each mapping must record its owning mesh and observed weight range in the intake
report. Bone-only models use `bone_fallback` with an explicit expression-bone map.

## Minimum acceptance

- Original channel inventory is preserved.
- Every claimed mapping changes a live mesh or mapped facial bone.
- Neutral reset removes residual weights.
- Crossfades do not double-apply aliases or leave channels stuck.
- Blink closes the correct eyelids; vowels do not invert or distort the jaw.
- Unsupported semantic channels remain explicit and degrade safely.
- Close-up visual evidence exists for each accepted character.
