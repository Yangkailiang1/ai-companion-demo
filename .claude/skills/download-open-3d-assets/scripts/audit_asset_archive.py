"""Audit a ZIP archive before extraction into the 3D asset pipeline."""

from __future__ import annotations

import argparse
import json
import stat
import sys
import zipfile
from collections import Counter
from pathlib import Path, PurePosixPath

MODEL_EXTENSIONS = {".glb", ".gltf", ".fbx", ".obj", ".blend"}
FORBIDDEN_EXTENSIONS = {".app", ".bat", ".cmd", ".com", ".dmg", ".exe", ".js", ".msi", ".pkg", ".sh"}
ARCHIVE_EXTENSIONS = {".7z", ".rar", ".tar", ".tgz", ".zip"}


def main() -> int:
    """Report archive safety, formats and extraction budget without extracting."""
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("--max-uncompressed-bytes", type=int, default=1024 * 1024 * 1024)
    parser.add_argument("--json-output", type=Path)
    args = parser.parse_args()
    errors: list[str] = []
    counts: Counter[str] = Counter()
    total = 0
    try:
        with zipfile.ZipFile(args.archive) as bundle:
            for entry in bundle.infolist():
                path = PurePosixPath(entry.filename)
                suffix = path.suffix.lower()
                if path.is_absolute() or ".." in path.parts:
                    errors.append(f"unsafe path: {entry.filename}")
                mode = entry.external_attr >> 16
                if stat.S_ISLNK(mode):
                    errors.append(f"symlink rejected: {entry.filename}")
                if suffix in FORBIDDEN_EXTENSIONS:
                    errors.append(f"executable rejected: {entry.filename}")
                if suffix in ARCHIVE_EXTENSIONS:
                    errors.append(f"nested archive rejected: {entry.filename}")
                if suffix:
                    counts[suffix] += 1
                total += entry.file_size
    except (OSError, zipfile.BadZipFile) as exc:
        errors.append(str(exc))
    if total > args.max_uncompressed_bytes:
        errors.append(f"uncompressed size {total} exceeds budget")
    model_count = sum(counts[extension] for extension in MODEL_EXTENSIONS)
    if model_count == 0:
        errors.append("no supported 3D model files")
    report = {
        "archive": str(args.archive),
        "safe": not errors,
        "uncompressed_bytes": total,
        "model_count": model_count,
        "formats": {key: counts[key] for key in sorted(MODEL_EXTENSIONS) if counts[key]},
        "errors": errors,
    }
    if args.json_output:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    if errors:
        for error in errors:
            print(f"OPEN_ASSET_ARCHIVE_FAIL: {error}", file=sys.stderr)
        return 1
    print(
        f"OPEN_ASSET_ARCHIVE_PASS models={model_count} bytes={total} "
        f"formats={json.dumps(report['formats'], sort_keys=True)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
