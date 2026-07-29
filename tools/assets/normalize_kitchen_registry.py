"""Normalize quarantined Poly Haven kitchen assets into Godot Registry candidates.

Roadmap: S4.1, S4.2
Side effects: Copies files to assets/props/, writes Registry candidate JSON.
"""
from __future__ import annotations

import hashlib
import json
import os
import pathlib
import shutil
import sys
import tempfile

PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[2]
QUARANTINE_ROOT = pathlib.Path("/tmp/asset_quarantine/polyhaven")
OUTPUT_ROOT = PROJECT_ROOT / "assets" / "props" / "polyhaven"
REGISTRY_DIR = PROJECT_ROOT / "data" / "scene_generation" / "asset_registry_candidates"
REVIEWED_GEOMETRY = {
    "woodentable_01": {
        "source_sha256": "413804e054055c397b4cfbd0916027097d2a20853b165b533007a46d131e1d17",
        "aabb_m": [1.799648, 0.548849, 0.657175],
        "front_axis": "+Z",
        "up_axis": "+Y",
        "status": "previewed",
    },
    "woodenchair_01": {
        "source_sha256": "d7139c63be77bb91ceb25cb38733008156bf93d2299a6ca4673ea3c49f5fdec6",
        "aabb_m": [0.688173, 2.273515, 0.658462],
        "front_axis": "+Z",
        "up_axis": "+Y",
        "status": "previewed",
    },
    "ceramic_vase_01": {
        "source_sha256": "4e2c69eb5bbccf86e9fbf92af438464669d804c1f0eae041ee28651a5b57d91e",
        "aabb_m": [0.203634, 0.400268, 0.203636],
        "front_axis": "+Z",
        "up_axis": "+Y",
        "status": "previewed",
    },
}


def _dir_sha256(directory: pathlib.Path) -> str:
    """Return a stable ordered tree hash.

    Roadmap: O2.1
    Side effects: None.
    """
    digest = hashlib.sha256()
    for fp in sorted(directory.rglob("*")):
        if fp.is_file():
            digest.update(fp.relative_to(directory).as_posix().encode())
            digest.update(fp.read_bytes())
    return digest.hexdigest()


def read_gltf_triangle_count(gltf_path: pathlib.Path) -> tuple[int, int]:
    """Count triangles and vertices from a GLTF JSON.

    Roadmap: O2.1
    Returns (triangle_count, vertex_count) — 0 for both if unparseable.
    """
    try:
        gltf_data = json.loads(gltf_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return 0, 0

    tris = 0
    verts = 0
    accessors = gltf_data.get("accessors", [])
    for mesh in gltf_data.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            indices_accessor = primitive.get("indices")
            pos_accessor = primitive.get("attributes", {}).get("POSITION")

            if indices_accessor is not None and indices_accessor < len(accessors):
                acc = accessors[indices_accessor]
                tris += acc.get("count", 0) // 3

            if pos_accessor is not None and pos_accessor < len(accessors):
                acc = accessors[pos_accessor]
                verts += acc.get("count", 0)

    return tris, verts


def _assign_roles(asset_lower: str) -> dict:
    """Derive candidate roles without inventing interaction affordances.

    Roadmap: O2.1
    Side effects: None.
    """
    if "vase" in asset_lower:
        return {
            "visual": "decor",
            "physics": "static",
            "semantic": ["observable"],
            "placement": "surface",
            "style_tags": ["modern", "ceramic", "indoor"],
        }
    elif "chair" in asset_lower:
        return {
            "visual": "furniture",
            "physics": "static",
            "semantic": ["observable"],
            "placement": "floor",
            "style_tags": ["gothic", "victorian", "wooden", "indoor"],
        }
    elif "table" in asset_lower:
        return {
            "visual": "furniture",
            "physics": "static",
            "semantic": ["observable"],
            "placement": "floor",
            "style_tags": ["vintage", "worn", "wooden", "indoor"],
        }
    else:
        return {
            "visual": "furniture",
            "physics": "static",
            "semantic": ["observable"],
            "placement": "floor",
            "style_tags": ["modern", "indoor"],
        }


def _validate_source(source_dir: pathlib.Path, source_id: str, normalize_id: str) -> pathlib.Path:
    """Verify source directory, GLTF file, and provenance exist before any copy.

    Roadmap: O2.1
    Returns the path to the main GLTF file.
    Raises FileNotFoundError or ValueError on failure.
    """
    if not source_dir.is_dir():
        raise FileNotFoundError(
            f"Source directory not found: {source_dir} "
            f"(source_id={source_id}, normalize_id={normalize_id})"
        )

    gltf_files = sorted(source_dir.glob("*.gltf"))
    if not gltf_files:
        raise FileNotFoundError(f"No GLTF file found in {source_dir}")

    # Verify the .bin companion exists for each GLTF that references it
    for gf in gltf_files:
        try:
            gdata = json.loads(gf.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        for buf in gdata.get("buffers", []):
            uri = buf.get("uri", "")
            if uri and not (source_dir / uri).exists():
                raise FileNotFoundError(f"Missing buffer '{uri}' for {gf.name}")

    provenance_path = source_dir / f"{source_id}.provenance.json"
    if not provenance_path.exists():
        raise FileNotFoundError(f"Provenance manifest not found: {provenance_path}")
    provenance = json.loads(provenance_path.read_text(encoding="utf-8"))
    if provenance.get("asset_id") != source_id:
        raise ValueError(f"Provenance asset_id mismatch for {source_id}")
    if provenance.get("redistribution") != "allowed":
        raise ValueError(f"Public normalization denied for {source_id}")

    return gltf_files[0]


def _publish_stage(stage_dir: pathlib.Path, target_dir: pathlib.Path) -> None:
    """Atomically publish one validated stage with rollback.

    Roadmap: O2.1
    Side effects: Replaces only the target asset directory.
    """
    backup_dir = target_dir.with_name(f".{target_dir.name}.backup")
    if backup_dir.exists():
        shutil.rmtree(backup_dir)
    if target_dir.exists():
        os.replace(target_dir, backup_dir)
    try:
        os.replace(stage_dir, target_dir)
    except Exception:
        if backup_dir.exists() and not target_dir.exists():
            os.replace(backup_dir, target_dir)
        raise
    if backup_dir.exists():
        shutil.rmtree(backup_dir)


def normalize_asset(
    source_id: str,
    provenance: dict,
    *,
    quarantine_root: pathlib.Path = QUARANTINE_ROOT,
    output_root: pathlib.Path = OUTPUT_ROOT,
    project_root: pathlib.Path = PROJECT_ROOT,
) -> dict:
    """Copy from quarantine to the project through a validated atomic stage.

    Roadmap: O2.1
    source_id: Poly Haven provided name (e.g. 'WoodenTable_01')
    normalize_id: lowercase project ID (e.g. 'woodentable_01')

    The target directory uses the normalized ID. Source quarantine directory
    uses the original source ID which may differ in case.
    """
    normalize_id = source_id.lower()
    source_dir = quarantine_root / source_id
    target_dir = output_root / normalize_id

    print(f"[registry] {source_id} → {normalize_id}")

    # ---- Pre-validation (before touching target) ----
    source_gltf = _validate_source(source_dir, source_id, normalize_id)
    if provenance.get("asset_id") != source_id:
        raise ValueError(f"Caller provenance mismatch for {source_id}")
    if provenance.get("redistribution") != "allowed":
        raise ValueError(f"Caller provenance denies public normalization for {source_id}")
    reviewed = REVIEWED_GEOMETRY.get(normalize_id, {})
    if reviewed.get("source_sha256") != provenance.get("sha256"):
        reviewed = {}
    geometry_review = reviewed or {
        "aabb_m": [0, 0, 0],
        "front_axis": "unknown",
        "up_axis": "unknown",
        "status": "inventoried",
    }

    target_dir.parent.mkdir(parents=True, exist_ok=True)
    tmp_dir = pathlib.Path(tempfile.mkdtemp(
        prefix=f"normalize_{normalize_id}_", dir=target_dir.parent
    ))
    try:
        for item in source_dir.iterdir():
            dest = tmp_dir / item.name
            if item.is_dir():
                shutil.copytree(item, dest)
            elif item.is_file():
                shutil.copy2(item, dest)

        # Verify the copy
        dest_gltf_list = sorted(tmp_dir.glob("*.gltf"))
        if not dest_gltf_list:
            raise FileNotFoundError(f"GLTF missing after temp copy: {tmp_dir}")

        public_provenance = dict(provenance)
        public_provenance["main_file"] = (
            f"res://assets/props/polyhaven/{normalize_id}/{source_gltf.name}"
        )
        normalized_roles = _assign_roles(normalize_id)
        public_provenance["intended_archetype"] = (
            "decor" if normalized_roles["visual"] == "decor" else "static_furniture"
        )
        public_provenance["style_tags"] = normalized_roles["style_tags"]
        public_provenance["status"] = geometry_review["status"]
        (tmp_dir / f"{source_id}.provenance.json").write_text(
            json.dumps(public_provenance, indent=2, ensure_ascii=False) + os.linesep,
            encoding="utf-8",
        )

        _publish_stage(tmp_dir, target_dir)
        tmp_dir = None  # moved successfully
    finally:
        if tmp_dir is not None and tmp_dir.exists():
            shutil.rmtree(tmp_dir)

    # ---- Read triangle count from final target ----
    gltf_path = target_dir / source_gltf.name
    tris, verts = read_gltf_triangle_count(gltf_path)

    # Generate resource path (relative to project root, no machine paths)
    rel_path = gltf_path.relative_to(project_root)
    resource_path = f"res://{rel_path.as_posix()}"

    # Assign roles based on normalized ID
    roles_data = _assign_roles(normalize_id)
    style_tags = roles_data.pop("style_tags", [])

    # Compute stable target hash for idempotency
    target_hash = _dir_sha256(target_dir)

    # Build Registry candidate entry
    candidate = {
        "schema_version": 1,
        "asset_id": normalize_id,
        "source_id": source_id,
        "resource_path": resource_path,
        "resource_hash": target_hash,
        "provenance": {
            "provider": provenance.get("provider", "polyhaven"),
            "official_page": provenance.get("official_page", ""),
            "license": provenance.get("license", "CC0-1.0"),
            "redistribution": provenance.get("redistribution", "allowed"),
            "source_sha256": provenance.get("sha256", ""),
        },
        "geometry": {
            "aabb_m": geometry_review["aabb_m"],
            "front_axis": geometry_review["front_axis"],
            "up_axis": geometry_review["up_axis"],
            "triangle_count": tris,
        },
        "roles": roles_data,
        "style_tags": style_tags,
        "interaction_profile": "",
        "status": geometry_review["status"],
    }

    print(f"  [registry] {normalize_id}: tris={tris} verts={verts} path={resource_path} hash={target_hash[:16]}")
    return candidate


def main() -> int:
    """Normalize downloaded candidates and write a Registry candidate batch.

    Roadmap: O2.1
    Side effects: Publishes candidates and writes one Registry JSON file.
    """
    batch_path = QUARANTINE_ROOT / "batch_provenance.json"
    if not batch_path.exists():
        print(f"ERROR: batch provenance not found at {batch_path}", file=sys.stderr)
        return 1

    batch = json.loads(batch_path.read_text(encoding="utf-8"))
    candidates = []

    source_ids = batch.get("candidates", batch.get("accepted", []))
    for source_id in source_ids:
        provenance_path = QUARANTINE_ROOT / source_id / f"{source_id}.provenance.json"
        if not provenance_path.exists():
            print(f"ERROR: provenance not found for {source_id}", file=sys.stderr)
            continue
        provenance = json.loads(provenance_path.read_text(encoding="utf-8"))
        try:
            candidate = normalize_asset(source_id, provenance)
            candidates.append(candidate)
        except Exception as exc:
            print(f"ERROR: {source_id} → {exc}", file=sys.stderr)

    # Write Registry candidate JSON
    REGISTRY_DIR.mkdir(parents=True, exist_ok=True)
    output_path = REGISTRY_DIR / "polyhaven_kitchen_batch_01.json"
    output_text = json.dumps(candidates, indent=2, ensure_ascii=False) + os.linesep
    output_path.write_text(output_text, encoding="utf-8")

    print()
    print("=" * 60)
    print("REGISTRY_CANDIDATE_BATCH_REPORT")
    print(f"  candidates: {len(candidates)}")
    print(f"  output: {output_path}")
    for c in candidates:
        print(f"  ✓ {c['asset_id']} tris={c['geometry']['triangle_count']} status={c['status']}")
    print("=" * 60)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
