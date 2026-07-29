"""Download 3 Poly Haven CC0 indoor models for kitchen/dining expansion.

Roadmap: S4.0, S4.1
Side effects: Downloads to quarantine directory, writes provenance manifests.
"""

from __future__ import annotations

import hashlib
import json
import os
import pathlib
import sys
import urllib.request
from datetime import date

USER_AGENT = "ai-companion-demo-asset-import/0.1 (local development)"
ASSETS = [
    "WoodenTable_01",
    "WoodenChair_01",
    "ceramic_vase_01",
]
RESOLUTION = "1k"

ASSETS_CONFIG = {
    "WoodenTable_01": {
        "intended_archetype": "static_furniture",
        "style_tags": ["vintage", "worn", "wooden", "indoor"],
    },
    "WoodenChair_01": {
        "intended_archetype": "static_furniture",
        "style_tags": ["gothic", "victorian", "wooden", "indoor"],
    },
    "ceramic_vase_01": {
        "intended_archetype": "decor",
        "style_tags": ["modern", "ceramic", "indoor"],
    },
}

PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[2]
QUARANTINE_ROOT = pathlib.Path("/tmp/asset_quarantine/polyhaven")


def fetch_json(url: str) -> dict:
    """Fetch one official provider record.

    Roadmap: O2.1
    Side effects: Performs one HTTPS request.
    """
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def download_file(url: str, target: pathlib.Path) -> None:
    """Download one missing dependency into quarantine.

    Roadmap: O2.1
    Side effects: Writes one quarantine file.
    """
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() and target.stat().st_size > 0:
        return
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response:
        target.write_bytes(response.read())


def sha256_file(path: pathlib.Path) -> str:
    """Return a file SHA-256; pure read.

    Roadmap: O2.1
    """
    digest = hashlib.sha256()
    with path.open("rb") as f:
        while chunk := f.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def download_asset(asset: str) -> dict:
    """Download one Poly Haven asset without granting visual acceptance.

    Roadmap: O2.1
    Side effects: Writes a quarantined asset and provenance manifest.
    """
    print(f"[polyhaven] Fetching metadata: {asset}")
    metadata = fetch_json(f"https://api.polyhaven.com/files/{asset}")
    package = metadata["gltf"][RESOLUTION]["gltf"]
    asset_dir = QUARANTINE_ROOT / asset

    # Per-asset archetype and style config
    cfg = ASSETS_CONFIG.get(asset, {"intended_archetype": "static_furniture", "style_tags": ["modern", "indoor"]})

    # Download main gltf
    gltf_name = pathlib.Path(package["url"]).name
    download_file(package["url"], asset_dir / gltf_name)
    gltf_hash = sha256_file(asset_dir / gltf_name)

    total_bytes = int(package.get("size", 0))
    included = {}
    for relative_path, file_info in package.get("include", {}).items():
        download_file(file_info["url"], asset_dir / relative_path)
        file_hash = sha256_file(asset_dir / relative_path)
        file_bytes = int(file_info.get("size", 0))
        total_bytes += file_bytes
        included[relative_path] = {
            "url": file_info["url"],
            "size": file_bytes,
            "sha256": file_hash,
        }

    # Provenance manifest — download is the first stage, not acceptance.
    provenance = {
        "schema_version": 1,
        "asset_id": asset,
        "provider": "polyhaven",
        "official_page": f"https://polyhaven.com/a/{asset}",
        "download_url": package["url"],
        "license": "CC0-1.0",
        "redistribution": "allowed",
        "accessed_at": date.today().isoformat(),
        "resolution": RESOLUTION,
        "main_file": f"{asset}/{gltf_name}",
        "sha256": gltf_hash,
        "bytes": total_bytes,
        "included_files": included,
        "intended_archetype": cfg["intended_archetype"],
        "style_tags": cfg["style_tags"],
        "status": "downloaded",
    }

    provenance_path = asset_dir / f"{asset}.provenance.json"
    provenance_path.write_text(
        json.dumps(provenance, indent=2, ensure_ascii=False) + os.linesep,
        encoding="utf-8",
    )

    print(f"  [polyhaven] {asset}: {gltf_name} sha256={gltf_hash[:16]}... bytes={total_bytes}")

    return provenance


def main() -> int:
    """Download the bounded batch and report unaccepted candidates.

    Roadmap: O2.1
    Side effects: Writes the quarantine batch manifest.
    """
    QUARANTINE_ROOT.mkdir(parents=True, exist_ok=True)
    candidates = []
    errors = []

    for asset in ASSETS:
        try:
            record = download_asset(asset)
            candidates.append(record)
            print(f"  [polyhaven] DOWNLOADED_CANDIDATE: {asset}")
        except Exception as exc:
            errors.append({"asset": asset, "error": str(exc)})
            print(f"  [polyhaven] REJECTED: {asset} — {exc}", file=sys.stderr)

    # Batch manifest
    batch = {
        "batch_id": "polyhaven_kitchen_batch_01",
        "date": "2026-07-29",
        "pipeline": "download-open-3d-assets",
        "provider": "polyhaven",
        "license": "CC0-1.0",
        "resolution": RESOLUTION,
        "candidates": [a["asset_id"] for a in candidates],
        "rejected": [e["asset"] for e in errors],
        "quarantine_dir": str(QUARANTINE_ROOT),
    }
    manifest_path = QUARANTINE_ROOT / "batch_provenance.json"
    manifest_path.write_text(
        json.dumps(batch, indent=2, ensure_ascii=False) + os.linesep,
        encoding="utf-8",
    )

    # Summary report
    print()
    print("=" * 60)
    print("OPEN_ASSET_DOWNLOAD_BATCH_REPORT")
    print(f"  downloaded_candidates: {len(candidates)}")
    print(f"  rejected: {len(errors)}")
    print(f"  quarantine: {QUARANTINE_ROOT}")
    print(f"  batch_manifest: {manifest_path}")
    for a in candidates:
        print(f"  ✓ {a['asset_id']} sha256={a['sha256'][:16]}... bytes={a['bytes']}")
    for e in errors:
        print(f"  ✗ {e['asset']} error={e['error']}")
    print("=" * 60)

    return 0 if candidates else 1


if __name__ == "__main__":
    raise SystemExit(main())
