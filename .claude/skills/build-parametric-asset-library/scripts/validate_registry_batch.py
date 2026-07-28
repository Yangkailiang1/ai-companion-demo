"""Validate a small batch of parametric Asset Registry candidates."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")
VISUAL_ROLES = {"structure", "furniture", "decor", "clutter", "lighting"}
PHYSICS_ROLES = {"none", "static", "rigid", "trigger"}
SEMANTIC_CAPABILITIES = {"observable", "interactable", "stateful", "portable"}
PLACEMENTS = {"floor", "wall", "surface", "ceiling", "modular_grid"}
STATUSES = {"inventoried", "imported", "measured", "previewed", "accepted"}


def validate(entry: dict, project_root: Path) -> list[str]:
    """Return stable validation errors for one candidate."""
    errors: list[str] = []
    asset_id = str(entry.get("asset_id", ""))
    if entry.get("schema_version") != 1:
        errors.append("schema_version must be 1")
    if not ID_PATTERN.fullmatch(asset_id):
        errors.append("asset_id must be stable snake_case")
    resource_path = str(entry.get("resource_path", ""))
    if not resource_path.startswith("res://") or ".." in Path(resource_path).parts:
        errors.append("resource_path must be safe res://")
    elif not (project_root / resource_path.removeprefix("res://")).is_file():
        errors.append("resource_path does not exist")
    provenance = entry.get("provenance", {})
    if provenance.get("license") not in {"CC0", "CC0-1.0", "Project-authored"}:
        errors.append("license is not approved")
    if provenance.get("redistribution") != "allowed":
        errors.append("redistribution must be allowed")
    if not str(provenance.get("official_page", "")).startswith("https://"):
        errors.append("official_page is required")
    status = entry.get("status")
    geometry = entry.get("geometry", {})
    aabb = geometry.get("aabb_m")
    is_measured = status in {"measured", "previewed", "accepted"}
    vector_is_numeric = (
        isinstance(aabb, list)
        and len(aabb) == 3
        and all(isinstance(value, (int, float)) for value in aabb)
    )
    if not vector_is_numeric or (is_measured and not all(value > 0 for value in aabb)):
        errors.append("geometry.aabb_m is invalid for candidate status")
    valid_axes = {"+X", "-X", "+Y", "-Y", "+Z", "-Z"}
    allowed_axes = valid_axes if is_measured else valid_axes | {"unknown"}
    if geometry.get("front_axis") not in allowed_axes:
        errors.append("front_axis is invalid")
    if geometry.get("up_axis") not in allowed_axes:
        errors.append("up_axis is invalid")
    roles = entry.get("roles", {})
    if roles.get("visual") not in VISUAL_ROLES:
        errors.append("visual role is invalid")
    if roles.get("physics") not in PHYSICS_ROLES:
        errors.append("physics role is invalid")
    semantic = set(roles.get("semantic", []))
    if not semantic.issubset(SEMANTIC_CAPABILITIES):
        errors.append("semantic capabilities are invalid")
    if roles.get("placement") not in PLACEMENTS:
        errors.append("placement role is invalid")
    if semantic.intersection({"interactable", "stateful", "portable"}) and not entry.get(
        "interaction_profile"
    ):
        errors.append("interactive capabilities require interaction_profile")
    if status not in STATUSES:
        errors.append("status is invalid")
    return errors


def main() -> int:
    """Validate one JSON array with at most three same-archetype candidates."""
    parser = argparse.ArgumentParser()
    parser.add_argument("batch", type=Path)
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    args = parser.parse_args()
    try:
        entries = json.loads(args.batch.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"PARAMETRIC_REGISTRY_FAIL: {exc}", file=sys.stderr)
        return 1
    if not isinstance(entries, list) or not 1 <= len(entries) <= 3:
        print("PARAMETRIC_REGISTRY_FAIL: batch must contain 1-3 entries", file=sys.stderr)
        return 1
    failures = []
    for entry in entries:
        failures.extend(f"{entry.get('asset_id', '?')}: {error}" for error in validate(entry, args.project_root))
    if failures:
        for failure in failures:
            print(f"PARAMETRIC_REGISTRY_FAIL: {failure}", file=sys.stderr)
        return 1
    print(f"PARAMETRIC_REGISTRY_PASS assets={','.join(entry['asset_id'] for entry in entries)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
