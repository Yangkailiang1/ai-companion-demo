"""Extract bone, morph, material, and animation inventories from penguin.glb.

Roadmap: C6.1, O2.1
Side effects: Reads GLB, writes inventory JSON files.
"""

from __future__ import annotations

import hashlib
import json
import os
import pathlib
import struct
import sys

PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[2]
GLB_PATH = PROJECT_ROOT / "assets" / "characters" / "penguin" / "penguin.glb"
OUTPUT_DIR = PROJECT_ROOT / "assets" / "characters" / "penguin"


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        while chunk := f.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def extract_gltf_nodes(gltf_data: dict) -> list[dict]:
    """Extract bone hierarchy from GLTF nodes."""
    nodes = gltf_data.get("nodes", [])
    skins = gltf_data.get("skins", [])
    bones = []
    if skins:
        joint_indices = skins[0].get("joints", [])
        for idx in joint_indices:
            if idx < len(nodes):
                node = nodes[idx]
                bones.append({
                    "index": idx,
                    "name": node.get("name", f"bone_{idx}"),
                    "children": node.get("children", []),
                    "translation": node.get("translation"),
                    "rotation": node.get("rotation"),
                    "scale": node.get("scale"),
                })
    # Also include non-joint named nodes as "helpers"
    helpers = []
    for i, node in enumerate(nodes):
        if i not in (skins[0].get("joints", []) if skins else []):
            name = node.get("name", "")
            if name:
                helpers.append({"index": i, "name": name})
    return bones


def extract_morphs(gltf_data: dict) -> list[dict]:
    """Extract morph target / blend shape information."""
    meshes = gltf_data.get("meshes", [])
    morph_list = []
    for mi, mesh in enumerate(meshes):
        mesh_name = mesh.get("name", f"mesh_{mi}")
        weights = mesh.get("weights", [])
        for prim in mesh.get("primitives", []):
            targets = prim.get("targets", [])
            if not targets:
                continue
            # Get morph names from extras if available
            extras = mesh.get("extras", {})
            target_names = extras.get("targetNames", []) if extras else []

            for ti, target in enumerate(targets):
                name = target_names[ti] if ti < len(target_names) else f"morph_{ti:03d}"
                default_weight = weights[ti] if ti < len(weights) else 0.0
                morph_list.append({
                    "mesh": mesh_name,
                    "index": ti,
                    "name": name,
                    "default_weight": default_weight,
                })
    return morph_list


def extract_materials(gltf_data: dict) -> list[dict]:
    mats = gltf_data.get("materials", [])
    textures = gltf_data.get("textures", [])
    images = gltf_data.get("images", [])
    material_list = []
    for mi, mat in enumerate(mats):
        mat_name = mat.get("name", f"material_{mi}")
        pbr = mat.get("pbrMetallicRoughness", {})
        base_color = pbr.get("baseColorFactor")
        base_tex_idx = pbr.get("baseColorTexture", {}).get("index")
        alpha_mode = mat.get("alphaMode", "OPAQUE")
        base_tex_uri = ""
        if base_tex_idx is not None and base_tex_idx < len(textures):
            img_idx = textures[base_tex_idx].get("source")
            if img_idx is not None and img_idx < len(images):
                base_tex_uri = images[img_idx].get("uri", "")
        material_list.append({
            "index": mi,
            "name": mat_name,
            "base_color_factor": base_color,
            "base_color_texture": base_tex_uri,
            "alpha_mode": alpha_mode,
        })
    return material_list


def extract_animations(gltf_data: dict) -> list[dict]:
    animations = gltf_data.get("animations", [])
    anim_list = []
    for ai, anim in enumerate(animations):
        anim_name = anim.get("name", f"animation_{ai}")
        channels = anim.get("channels", [])
        samplers = anim.get("samplers", [])
        accessors = gltf_data.get("accessors", [])
        nodes = gltf_data.get("nodes", [])

        # Get duration from sampler output accessors
        max_time = 0.0
        affected_bones = set()
        for channel in channels:
            sampler = samplers[channel["sampler"]] if channel["sampler"] < len(samplers) else None
            if sampler:
                input_acc = accessors[sampler["input"]] if sampler["input"] < len(accessors) else {}
                for v in input_acc.get("max", []):
                    max_time = max(max_time, v)
                target_node = channel.get("target", {}).get("node")
                if target_node is not None and target_node < len(nodes):
                    affected_bones.add(nodes[target_node].get("name", str(target_node)))

        anim_list.append({
            "index": ai,
            "name": anim_name,
            "duration_seconds": max_time,
            "channel_count": len(channels),
            "affected_bones": sorted(affected_bones),
        })
    return anim_list


def main() -> int:
    if not GLB_PATH.exists():
        print(f"ERROR: {GLB_PATH} not found", file=sys.stderr)
        return 1

    print(f"[extract] Reading: {GLB_PATH}")
    with GLB_PATH.open("rb") as f:
        magic = struct.unpack("<I", f.read(4))[0]  # glTF magic: 0x46546C67
        version = struct.unpack("<I", f.read(4))[0]
        total_length = struct.unpack("<I", f.read(4))[0]

        # Read chunks until we find the JSON chunk (type 0x4E4F534A)
        gltf_data = None
        while f.tell() < total_length:
            chunk_length = struct.unpack("<I", f.read(4))[0]
            chunk_type = struct.unpack("<I", f.read(4))[0]
            chunk_data = f.read(chunk_length)
            if chunk_type == 0x4E4F534A:  # "JSON"
                gltf_data = json.loads(chunk_data.decode("utf-8"))
                break

    if gltf_data is None:
        print("ERROR: Could not find JSON chunk in GLB", file=sys.stderr)
        return 1

    # Extract inventories
    bones = extract_gltf_nodes(gltf_data)
    morphs = extract_morphs(gltf_data)
    materials = extract_materials(gltf_data)
    animations = extract_animations(gltf_data)
    file_hash = sha256_file(GLB_PATH)

    # Write bone inventory
    bone_inventory = {
        "schema_version": 1,
        "character_id": "penguin",
        "total_bones": len(bones),
        "bones": bones,
    }
    (OUTPUT_DIR / "bone_inventory.json").write_text(
        json.dumps(bone_inventory, indent=2, ensure_ascii=False) + os.linesep,
        encoding="utf-8",
    )

    # Write morph inventory
    morph_inventory = {
        "schema_version": 1,
        "character_id": "penguin",
        "total_morphs": len(morphs),
        "morphs": morphs,
    }
    (OUTPUT_DIR / "morph_inventory.json").write_text(
        json.dumps(morph_inventory, indent=2, ensure_ascii=False) + os.linesep,
        encoding="utf-8",
    )

    # Write animation inventory
    anim_inventory = {
        "schema_version": 1,
        "character_id": "penguin",
        "total_animations": len(animations),
        "animations": animations,
    }
    (OUTPUT_DIR / "animation_inventory.json").write_text(
        json.dumps(anim_inventory, indent=2, ensure_ascii=False) + os.linesep,
        encoding="utf-8",
    )

    # Write provenance
    # The penguin model license is unknown / private prototype only.
    # This script must never auto-promote unknown licenses to redistribution=allowed.
    provenance = {
        "schema_version": 1,
        "asset_id": "penguin",
        "provider": "local",
        "license": "unknown",
        "redistribution": "local_only",
        "license_note": "Source is a local .blend/.vrm archive with no redistribution terms. Treated as private prototype only.",
        "source_file": "assets/characters/penguin/penguin.glb",
        "source_sha256": file_hash,
        "conversion": {
            "source": "penguin.blend",
            "tool": "Blender",
            "script": "tools/blender/export_penguin.py",
            "animations": "tools/blender/generate_penguin_animations.py",
        },
    }
    (OUTPUT_DIR / "provenance.json").write_text(
        json.dumps(provenance, indent=2, ensure_ascii=False) + os.linesep,
        encoding="utf-8",
    )

    # Write conversion report
    conversion_report = {
        "schema_version": 1,
        "character_id": "penguin",
        "source_format": "Blender .blend",
        "output_format": "GLB",
        "output_sha256": file_hash,
        "output_bytes": GLB_PATH.stat().st_size,
        "bone_count": len(bones),
        "bone_names": [b["name"] for b in bones],
        "morph_count": len(morphs),
        "morph_names": [m["name"] for m in morphs],
        "material_count": len(materials),
        "material_names": [m["name"] for m in materials],
        "animation_count": len(animations),
        "animation_names": [a["name"] for a in animations],
    }
    (OUTPUT_DIR / "conversion_report.json").write_text(
        json.dumps(conversion_report, indent=2, ensure_ascii=False) + os.linesep,
        encoding="utf-8",
    )

    # Validate: unknown/private license must not claim redistribution=allowed.
    if provenance.get("redistribution") == "allowed":
        print("ERROR: unknown-license asset cannot declare redistribution=allowed", file=sys.stderr)
        return 1

    # Summary
    print(f"  Bones: {len(bones)}")
    print(f"  Morphs: {len(morphs)}")
    print(f"  Materials: {len(materials)}")
    print(f"  Animations: {len(animations)}")
    print(f"  SHA-256: {file_hash}")
    print(f"  Files written to: {OUTPUT_DIR}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
