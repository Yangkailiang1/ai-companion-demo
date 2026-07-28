# Asset Registry candidate contract

Each candidate JSON contains:

```json
{
  "schema_version": 1,
  "asset_id": "kaykit_armchair_pillows",
  "resource_path": "res://assets/props/kaykit/furniture_bits/armchair_pillows/armchair_pillows.gltf",
  "provenance": {
    "provider": "KayKit",
    "official_page": "https://kaylousberg.itch.io/furniture-bits",
    "license": "CC0-1.0",
    "redistribution": "allowed",
    "source_sha256": "..."
  },
  "geometry": {
    "aabb_m": [1.0, 1.0, 1.0],
    "front_axis": "-Z",
    "up_axis": "+Y",
    "triangle_count": 0
  },
  "roles": {
    "visual": "furniture",
    "physics": "static",
    "semantic": ["observable"],
    "placement": "floor"
  },
  "style_tags": ["low_poly", "cozy"],
  "interaction_profile": "",
  "status": "measured"
}
```

Allowed semantic capabilities are `observable`, `interactable`, `stateful`, and
`portable`. They are independent. `interaction_profile` is required whenever
`interactable`, `stateful`, or `portable` is present.

For `inventoried` and `imported`, geometry may use `aabb_m: [0, 0, 0]` and
`front_axis` / `up_axis: "unknown"`. These placeholders are rejected once status is
`measured` or later.

Candidate status progresses through:

`inventoried → imported → measured → previewed → accepted`.

Only `accepted` entries may be sampled by production Scene Recipes.
