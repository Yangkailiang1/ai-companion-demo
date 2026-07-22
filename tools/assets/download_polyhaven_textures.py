"""Download selected Poly Haven CC0 1K PBR texture maps for the living room."""

from __future__ import annotations

import json
import os
import pathlib
import urllib.request


USER_AGENT = "ai-companion-demo-asset-import/0.1 (local development)"
ASSETS = [
    "herringbone_parquet",
    "plastered_wall_04",
    "dirty_carpet",
]
MAPS = {
    "Diffuse": "diff",
    "nor_gl": "normal_gl",
    "arm": "arm",
}

PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[2]
OUTPUT_ROOT = PROJECT_ROOT / "assets" / "materials" / "polyhaven"


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


def main() -> None:
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    manifest = []
    for asset in ASSETS:
        metadata = fetch_json(f"https://api.polyhaven.com/files/{asset}")
        asset_dir = OUTPUT_ROOT / asset
        print(f"[polyhaven-texture] Fetching: {asset}")
        record = {
            "asset": asset,
            "source": f"https://polyhaven.com/a/{asset}",
            "license": "CC0",
            "resolution": "1k",
            "maps": {},
        }
        for api_key, local_key in MAPS.items():
            file_info = metadata[api_key]["1k"]["jpg"]
            file_name = pathlib.Path(file_info["url"]).name
            target = asset_dir / file_name
            download_file(file_info["url"], target)
            record["maps"][local_key] = str(target)
        manifest.append(record)

    manifest_path = OUTPUT_ROOT / "polyhaven_texture_manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + os.linesep,
        encoding="utf-8",
    )
    print(f"[polyhaven-texture] Wrote manifest: {manifest_path}")


if __name__ == "__main__":
    main()
