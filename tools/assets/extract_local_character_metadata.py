"""Batch extract metadata from local character GLBs for inventory manifests.

Roadmap: C6.1, O2.1
Side effects: Reads GLBs, writes inventory JSON per character.
"""

from __future__ import annotations

import hashlib
import json
import os
import pathlib
import struct
import sys

PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[2]
LOCAL_CHARS = ["cartethyia", "castorice", "xiangliyao"]


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        while chunk := f.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def read_glb_json(glb_path: pathlib.Path) -> dict | None:
    """Read JSON chunk from a GLB file."""
    with glb_path.open("rb") as f:
        magic = struct.unpack("<I", f.read(4))[0]
        if magic != 0x46546C67:
            return None
        f.read(4)  # version
        total_length = struct.unpack("<I", f.read(4))[0]
        while f.tell() < total_length:
            chunk_length = struct.unpack("<I", f.read(4))[0]
            chunk_type = struct.unpack("<I", f.read(4))[0]
            chunk_data = f.read(chunk_length)
            if chunk_type == 0x4E4F534A:  # JSON
                return json.loads(chunk_data.decode("utf-8"))
    return None


def extract_inventories(gltf: dict) -> dict:
    nodes = gltf.get("nodes", [])
    skins = gltf.get("skins", [])
    meshes = gltf.get("meshes", [])
    materials = gltf.get("materials", [])
    animations = gltf.get("animations", [])
    accessors = gltf.get("accessors", [])
    textures = gltf.get("textures", [])
    images = gltf.get("images", [])

    # Bones
    joints = skins[0].get("joints", []) if skins else []
    bones = []
    for j_idx in joints:
        if j_idx < len(nodes):
            n = nodes[j_idx]
            bones.append({
                "index": j_idx,
                "name": n.get("name", f"bone_{j_idx}"),
                "children": n.get("children", []),
            })

    # Morphs
    morphs = []
    for mi, mesh in enumerate(meshes):
        mesh_name = mesh.get("name", f"mesh_{mi}")
        weights = mesh.get("weights", [])
        for prim in mesh.get("primitives", []):
            targets = prim.get("targets", [])
            extras = mesh.get("extras", {})
            target_names = extras.get("targetNames", []) if extras else []
            for ti, target in enumerate(targets):
                name = target_names[ti] if ti < len(target_names) else f"morph_{ti:03d}"
                w = weights[ti] if ti < len(weights) else 0.0
                morphs.append({"mesh": mesh_name, "index": ti, "name": name, "default_weight": w})

    # Materials
    mat_list = []
    for mi, mat in enumerate(materials):
        pbr = mat.get("pbrMetallicRoughness", {})
        base_tex_idx = pbr.get("baseColorTexture", {}).get("index")
        base_tex_uri = ""
        if base_tex_idx is not None and base_tex_idx < len(textures):
            img_idx = textures[base_tex_idx].get("source")
            if img_idx is not None and img_idx < len(images):
                base_tex_uri = images[img_idx].get("uri", "")
        mat_list.append({
            "index": mi,
            "name": mat.get("name", f"material_{mi}"),
            "base_color_factor": pbr.get("baseColorFactor"),
            "base_color_texture": base_tex_uri,
            "alpha_mode": mat.get("alphaMode", "OPAQUE"),
        })

    # Animations
    anim_list = []
    for ai, anim in enumerate(animations):
        anim_name = anim.get("name", f"animation_{ai}")
        channels = anim.get("channels", [])
        samplers = anim.get("samplers", [])
        max_time = 0.0
        affected = set()
        for ch in channels:
            sampler = samplers[ch["sampler"]] if ch["sampler"] < len(samplers) else None
            if sampler:
                inp_acc = accessors[sampler["input"]] if sampler["input"] < len(accessors) else {}
                for v in inp_acc.get("max", []):
                    max_time = max(max_time, v)
            target_node = ch.get("target", {}).get("node")
            if target_node is not None and target_node < len(nodes):
                affected.add(nodes[target_node].get("name", str(target_node)))
        anim_list.append({
            "index": ai,
            "name": anim_name,
            "duration_seconds": max_time,
            "channel_count": len(channels),
            "affected_bones": sorted(affected),
        })

    # Triangle count
    tris = 0
    for mesh in meshes:
        for prim in mesh.get("primitives", []):
            idx_acc = prim.get("indices")
            if idx_acc is not None:
                acc = accessors[idx_acc]
                tris += acc.get("count", 0) // 3

    return {
        "bones": bones,
        "morphs": morphs,
        "materials": mat_list,
        "animations": anim_list,
        "triangle_count": tris,
    }


def process_character(char_id: str) -> dict:
    char_dir = PROJECT_ROOT / "assets" / "local_characters" / char_id
    glb_path = char_dir / f"{char_id}.glb"
    if not glb_path.exists():
        return {"error": f"GLB not found: {glb_path}"}

    print(f"  Processing: {char_id}")
    gltf = read_glb_json(glb_path)
    if gltf is None:
        return {"error": "Failed to read GLB"}

    inv = extract_inventories(gltf)
    file_hash = sha256_file(glb_path)
    file_size = glb_path.stat().st_size

    # Write provenance
    (char_dir / "provenance.json").write_text(json.dumps({
        "schema_version": 1,
        "character_id": char_id,
        "source_format": "PMX",
        "output_format": "GLB",
        "output_sha256": file_hash,
        "output_bytes": file_size,
        "license": "local_only",
        "redistribution": "local_only",
        "status": "local_noncommercial_validation",
    }, indent=2, ensure_ascii=False) + os.linesep, encoding="utf-8")

    # Write bone inventory
    (char_dir / "bone_inventory.json").write_text(json.dumps({
        "schema_version": 1,
        "character_id": char_id,
        "total_bones": len(inv["bones"]),
        "bones": inv["bones"],
    }, indent=2, ensure_ascii=False) + os.linesep, encoding="utf-8")

    # Write morph inventory
    (char_dir / "morph_inventory.json").write_text(json.dumps({
        "schema_version": 1,
        "character_id": char_id,
        "total_morphs": len(inv["morphs"]),
        "morphs": inv["morphs"],
    }, indent=2, ensure_ascii=False) + os.linesep, encoding="utf-8")

    # Write animation inventory
    (char_dir / "animation_inventory.json").write_text(json.dumps({
        "schema_version": 1,
        "character_id": char_id,
        "total_animations": len(inv["animations"]),
        "animations": inv["animations"],
    }, indent=2, ensure_ascii=False) + os.linesep, encoding="utf-8")

    # Count unique morph names across all meshes
    unique_morph_names = len(set(m["name"] for m in inv["morphs"]))

    # Write conversion report
    (char_dir / "conversion_report.json").write_text(json.dumps({
        "schema_version": 1,
        "character_id": char_id,
        "source_format": "PMX (via Blender import)",
        "output_format": "GLB",
        "output_sha256": file_hash,
        "output_bytes": file_size,
        "bone_count": len(inv["bones"]),
        "morph_binding_count": len(inv["morphs"]),
        "morph_unique_count": unique_morph_names,
        "material_count": len(inv["materials"]),
        "animation_count": len(inv["animations"]),
        "triangle_count": inv["triangle_count"],
    }, indent=2, ensure_ascii=False) + os.linesep, encoding="utf-8")

    return {
        "bones": len(inv["bones"]),
        "morphs": len(inv["morphs"]),
        "morphs_unique": unique_morph_names,
        "materials": len(inv["materials"]),
        "animations": len(inv["animations"]),
        "tris": inv["triangle_count"],
        "sha256": file_hash[:16],
        "bytes": file_size,
    }


def main() -> int:
    print("=== Local Character Batch ===")
    accepted = []
    rejected = []
    for char_id in LOCAL_CHARS:
        try:
            result = process_character(char_id)
            if "error" in result:
                rejected.append({"character": char_id, "error": result["error"]})
                print(f"  ✗ {char_id}: {result['error']}")
            else:
                accepted.append({"character": char_id, **result})
                print(f"  ✓ {char_id}: {result['bones']} bones, {result['morphs']}/{result['morphs_unique']} morphs (total/unique), "
                      f"{result['materials']} materials, {result['animations']} anims, "
                      f"{result['tris']} tris, {result['bytes']} bytes")
        except Exception as exc:
            rejected.append({"character": char_id, "error": str(exc)})
            print(f"  ✗ {char_id}: {exc}")

    print()
    print("=" * 60)
    print("CHARACTER_BATCH_REPORT")
    print(f"  accepted: {len(accepted)}")
    print(f"  rejected: {len(rejected)}")
    for a in accepted:
        print(f"  ✓ {a['character']}: bones={a['bones']} morphs={a['morphs']}/{a['morphs_unique']} (total/unique) anims={a['animations']} tris={a['tris']}")
    for r in rejected:
        print(f"  ✗ {r['character']}: {r['error']}")
    print("=" * 60)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
