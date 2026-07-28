# Character package contract

## Accepted inputs

| Input | Decision |
|---|---|
| `.glb` | Preferred; preserve mesh, skeleton, materials, morphs, animations |
| `.gltf` + `.bin` + textures | Accepted when dependencies are complete |
| `.fbx` | Offline Blender conversion required |
| `.pmx` / `.pmd` + textures | Local Blender/MMD conversion only; never runtime input |
| `.vrm` | Inventory and offline conversion unless a reviewed importer is installed |
| `.blend` | Offline export source; record Blender version and external dependencies |
| `.obj` | Static mesh only; reject as a rigged character source |

Textures should be PNG/JPEG or another Blender/Godot-readable raster format.
Missing toon ramps, sphere maps, alpha masks, or normal maps must be reported.

## Normalized output

```text
assets/characters/<character_id>/        # public license only
assets/local_characters/<character_id>/  # restricted, Git-ignored
├── model.glb
├── character_manifest.json
├── provenance.json
├── bone_inventory.json
├── morph_inventory.json
├── animation_inventory.json
└── conversion_report.json
```

The version-1 manifest owns identity, spawn dimensions, motion adapter, skeleton
aliases, and expression adapter. It must not own cognition state or memories.

## Minimum acceptance

- License classification and source/output SHA-256 are present.
- One visible model, one resolvable skeleton, no missing texture dependency.
- Forward axis, up axis, height in meters, origin, and floor contact are measured.
- Semantic bone candidates cover hips, spine/chest, head, arms, legs, and feet.
- Morph and animation inventories distinguish existing from actually accepted.
- Public packages contain no source whose terms prohibit redistribution.
- Godot import, adapter coverage, runtime binding, collision, idle pose, and visual
  preview pass.

Embedded clips and morphs remain inventories until the motion/expression skills
validate their semantics and playback.
