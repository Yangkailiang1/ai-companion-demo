# Interactable object specification

Create one JSON file per object under `data/interactable_objects/`. This file is the
review and batch-production contract; Godot runtime state remains in
`data/scene_config.json` and the scene.

Required shape:

```json
{
  "schema_version": 1,
  "roadmap": ["S3.6", "T2.1", "C4.3"],
  "asset": {
    "resource_path": "res://assets/props/vendor/asset/model.gltf",
    "source_url": "https://authoritative-source.example/asset",
    "license": "CC0",
    "expected_aabb_m": [0.6, 0.84, 0.02]
  },
  "object": {
    "id": "stable_snake_case_id",
    "name": "玩家可见名称",
    "type": "decor",
    "affordances": ["inspect", "look_at"],
    "initial_state": "初始状态"
  },
  "scene": {
    "scene_path": "res://scenes/living_room.tscn",
    "node_path": "WallArt",
    "body_type": "StaticBody3D",
    "collision": {"shape": "BoxShape3D", "size_m": [0.7, 1.0, 0.08]},
    "anchors": {
      "approach": [-3.1, 0.0, -2.9],
      "look": [-3.1, 1.6, -3.6]
    }
  },
  "validation": {
    "headless_test": "res://scripts/debug/interactable_asset_pipeline_check.gd",
    "visual_test": "res://scripts/debug/main_screenshot_check.gd"
  }
}
```

Allowed `object.type`: `decor`, `static_furniture`, `portable`, `stateful_device`,
`container`, `seat`, `consumable`.

Allowed `body_type`: `StaticBody3D`, `RigidBody3D`.

Anchor requirements:

- All objects: `approach`, `look`.
- Portable/consumable: at least one of `left_hand_grab`, `right_hand_grab`, plus
  `place`.
- Seat: `sit`.
- Container: `approach`, `look`, and one or more slot anchors documented by its state
  component.

The validator checks structure, resource existence, license metadata, positive meter
dimensions, stable IDs, anchor coverage, and test paths. Godot headless tests must
still verify live node binding and NavMesh safety.
