"""Download one approved open 3D asset manifest into quarantine.

Roadmap: S4.0, S4.1, O4.1
Side effects: Writes one downloaded file and a resolved manifest under --output-dir.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import urllib.parse
import urllib.request
from pathlib import Path

APPROVED_HOSTS = {
    "ambientcg.com",
    "api.polyhaven.com",
    "dl.polyhaven.org",
    "kenney.nl",
    "www.kenney.nl",
    "quaternius.com",
    "www.quaternius.com",
}
APPROVED_LICENSES = {"CC0", "CC0-1.0", "Creative Commons Zero v1.0 Universal"}
CHUNK_SIZE = 1024 * 1024


def fail(message: str) -> int:
    """Print a stable failure message."""
    print(f"OPEN_ASSET_DOWNLOAD_FAIL: {message}", file=sys.stderr)
    return 1


def main() -> int:
    """Validate the manifest, download atomically, and write the resolved hash."""
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--max-bytes", type=int, default=250 * 1024 * 1024)
    args = parser.parse_args()
    try:
        manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return fail(f"manifest unreadable: {exc}")

    url = str(manifest.get("download_url", ""))
    host = (urllib.parse.urlparse(url).hostname or "").lower()
    if host not in APPROVED_HOSTS:
        return fail(f"host not approved: {host}")
    if manifest.get("license") not in APPROVED_LICENSES:
        return fail("license is not approved CC0")
    if manifest.get("redistribution") != "allowed":
        return fail("redistribution must be explicitly allowed")
    if not str(manifest.get("official_page", "")).startswith("https://"):
        return fail("official_page is required")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    filename = Path(urllib.parse.urlparse(url).path).name or f"{manifest['asset_id']}.bin"
    destination = args.output_dir / filename
    partial = destination.with_suffix(destination.suffix + ".part")
    request = urllib.request.Request(url, headers={"User-Agent": "ai-companion-demo-assets/1.0"})
    digest = hashlib.sha256()
    total = 0
    try:
        with urllib.request.urlopen(request, timeout=60) as response, partial.open("wb") as stream:
            while chunk := response.read(CHUNK_SIZE):
                total += len(chunk)
                if total > args.max_bytes:
                    raise ValueError(f"download exceeds {args.max_bytes} bytes")
                digest.update(chunk)
                stream.write(chunk)
    except (OSError, ValueError) as exc:
        partial.unlink(missing_ok=True)
        return fail(str(exc))

    actual_hash = digest.hexdigest()
    expected_hash = str(manifest.get("expected_sha256", "")).lower()
    if expected_hash and actual_hash != expected_hash:
        partial.unlink(missing_ok=True)
        return fail("SHA-256 mismatch")
    partial.replace(destination)
    resolved = dict(manifest)
    resolved.update({"sha256": actual_hash, "bytes": total, "local_file": destination.name})
    resolved_path = args.output_dir / f"{manifest['asset_id']}.provenance.json"
    resolved_path.write_text(json.dumps(resolved, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"OPEN_ASSET_DOWNLOAD_PASS asset={manifest['asset_id']} bytes={total} sha256={actual_hash}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
