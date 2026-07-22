"""Download selected Poly Haven CC0 glTF model assets for the living room.

The script downloads the 1K glTF package and all referenced include files into
`assets/props/polyhaven/<asset>/`, preserving relative texture/bin paths so Godot
can import the `.gltf` files directly.
"""

from __future__ import annotations

import json
import os
import pathlib
import urllib.request


USER_AGENT = "ai-companion-demo-asset-import/0.1 (local development)"
ASSETS = [
    "Sofa_01",
    "modern_coffee_table_01",
    "Television_01",
    "potted_plant_01",
    "Shelf_01",
    "modern_ceiling_lamp_01",
    "hanging_picture_frame_01",
]

PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[2]
OUTPUT_ROOT = PROJECT_ROOT / "assets" / "props" / "polyhaven"


def fetch_json(url: str) -> dict:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def download_file(url: str, target: pathlib.Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() and target.stat().st_size > 0:
        return
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response:
        target.write_bytes(response.read())


def download_asset(asset: str) -> dict:
    print(f"[polyhaven] Fetching metadata: {asset}")
    metadata = fetch_json(f"https://api.polyhaven.com/files/{asset}")
    package = metadata["gltf"]["1k"]["gltf"]
    asset_dir = OUTPUT_ROOT / asset

    gltf_name = pathlib.Path(package["url"]).name
    download_file(package["url"], asset_dir / gltf_name)

    total_size = int(package.get("size", 0))
    files = [str(asset_dir / gltf_name)]
    for relative_path, file_info in package.get("include", {}).items():
        download_file(file_info["url"], asset_dir / relative_path)
        total_size += int(file_info.get("size", 0))
        files.append(str(asset_dir / relative_path))

    return {
        "asset": asset,
        "source": f"https://polyhaven.com/a/{asset}",
        "license": "CC0",
        "resolution": "1k",
        "entry": str(asset_dir / gltf_name),
        "declared_size_bytes": total_size,
        "file_count": len(files),
    }


def main() -> None:
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    manifest = []
    for asset in ASSETS:
        record = download_asset(asset)
        manifest.append(record)
        print(
            f"[polyhaven] Ready: {asset} files={record['file_count']} "
            f"size≈{record['declared_size_bytes'] / 1024 / 1024:.2f}MB"
        )

    manifest_path = OUTPUT_ROOT / "polyhaven_manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + os.linesep,
        encoding="utf-8",
    )
    print(f"[polyhaven] Wrote manifest: {manifest_path}")


if __name__ == "__main__":
    main()
