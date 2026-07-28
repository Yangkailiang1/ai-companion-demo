"""Validate the durable contract for a Godot interactable 3D object.

Roadmap: S3.6, T2.1, C4.3, O4.1
Responsibility: Validate metadata and local paths; never mutate project files.
Tests: Run against data/interactable_objects/wall_art.json.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

ALLOWED_TYPES = {
    "decor",
    "static_furniture",
    "portable",
    "stateful_device",
    "container",
    "seat",
    "consumable",
}
ALLOWED_BODIES = {"StaticBody3D", "RigidBody3D"}
PORTABLE_TYPES = {"portable", "consumable"}
ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")


def _require(condition: bool, message: str, errors: list[str]) -> None:
    """Append a stable validation error when a contract condition fails.

    Roadmap: T2.1
    Side effects: Mutates only the caller-owned error list.
    """
    if not condition:
        errors.append(message)


def _vector3(value: Any) -> bool:
    """Return whether a value is a finite positive/position Vector3 array.

    Roadmap: C4.3
    Side effects: None.
    """
    return (
        isinstance(value, list)
        and len(value) == 3
        and all(isinstance(item, (int, float)) for item in value)
    )


def _resource_file(resource_path: str, project_root: Path) -> Path | None:
    """Resolve a res:// path without accepting absolute or parent traversal.

    Roadmap: O4.1, T2.1
    Side effects: None.
    """
    if not resource_path.startswith("res://"):
        return None
    relative = resource_path.removeprefix("res://")
    if ".." in Path(relative).parts:
        return None
    return project_root / relative


def validate(spec: dict[str, Any], project_root: Path) -> list[str]:
    """Validate schema, licensing, physics, anchors, and acceptance paths.

    Roadmap: S3.6, T2.1, C4.3
    Side effects: Reads referenced project files only.
    """
    errors: list[str] = []
    _require(spec.get("schema_version") == 1, "schema_version must be 1", errors)
    asset = spec.get("asset", {})
    obj = spec.get("object", {})
    scene = spec.get("scene", {})
    validation = spec.get("validation", {})

    resource_path = str(asset.get("resource_path", ""))
    resource_file = _resource_file(resource_path, project_root)
    _require(resource_file is not None, "asset.resource_path must be a safe res:// path", errors)
    _require(resource_file is not None and resource_file.is_file(), "asset resource does not exist", errors)
    source_url = str(asset.get("source_url", ""))
    license_name = str(asset.get("license", "")).strip()
    is_project_authored = source_url == "project-authored"
    _require(
        source_url.startswith("http") or is_project_authored,
        "asset.source_url must be http(s) or project-authored",
        errors,
    )
    _require(bool(license_name), "asset.license is required", errors)
    _require(
        not is_project_authored or license_name == "Project-authored",
        "project-authored assets require license=Project-authored",
        errors,
    )
    aabb = asset.get("expected_aabb_m")
    _require(_vector3(aabb) and all(float(v) > 0 for v in aabb or []),
             "asset.expected_aabb_m must contain three positive meter values", errors)

    object_id = str(obj.get("id", ""))
    object_type = str(obj.get("type", ""))
    _require(bool(ID_PATTERN.fullmatch(object_id)), "object.id must be stable snake_case", errors)
    _require(bool(str(obj.get("name", "")).strip()), "object.name is required", errors)
    _require(object_type in ALLOWED_TYPES, "object.type is unsupported", errors)
    _require(bool(obj.get("affordances")), "object.affordances must not be empty", errors)

    body_type = str(scene.get("body_type", ""))
    _require(body_type in ALLOWED_BODIES, "scene.body_type is unsupported", errors)
    if object_type in PORTABLE_TYPES:
        _require(body_type == "RigidBody3D", "portable objects require RigidBody3D", errors)
    collision = scene.get("collision", {})
    size = collision.get("size_m")
    _require(_vector3(size) and all(float(v) > 0 for v in size or []),
             "scene.collision.size_m must contain positive meter values", errors)
    anchors = scene.get("anchors", {})
    _require(_vector3(anchors.get("approach")), "approach anchor is required", errors)
    _require(_vector3(anchors.get("look")), "look anchor is required", errors)
    if object_type in PORTABLE_TYPES:
        has_grab = _vector3(anchors.get("left_hand_grab")) or _vector3(
            anchors.get("right_hand_grab")
        )
        _require(has_grab and _vector3(anchors.get("place")),
                 "portable objects require grab and place anchors", errors)
    if object_type == "seat":
        _require(_vector3(anchors.get("sit")), "seat requires sit anchor", errors)

    for key in ("scene_path",):
        path = _resource_file(str(scene.get(key, "")), project_root)
        _require(path is not None and path.is_file(), f"scene.{key} does not exist", errors)
    for key in ("headless_test", "visual_test"):
        path = _resource_file(str(validation.get(key, "")), project_root)
        _require(path is not None and path.is_file(), f"validation.{key} does not exist", errors)
    return errors


def main() -> int:
    """Load one specification and print a machine-readable pass/fail summary.

    Roadmap: T4.5, O4.1
    Side effects: Reads files and writes diagnostics to stdout/stderr.
    """
    parser = argparse.ArgumentParser()
    parser.add_argument("spec", type=Path)
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    args = parser.parse_args()
    try:
        spec = json.loads(args.spec.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"INTERACTABLE_SPEC_FAIL: {exc}", file=sys.stderr)
        return 1
    errors = validate(spec, args.project_root.resolve())
    if errors:
        for error in errors:
            print(f"INTERACTABLE_SPEC_FAIL: {error}", file=sys.stderr)
        return 1
    print(f"INTERACTABLE_SPEC_PASS object={spec['object']['id']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
