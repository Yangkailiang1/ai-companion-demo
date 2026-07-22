#!/usr/bin/env python3
"""Validate a reusable HumanML3D retarget package before baking it into a character."""

from __future__ import annotations

import argparse
import json
import pathlib

import numpy as np


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("package_dir", type=pathlib.Path)
    args = parser.parse_args()

    package_dir = args.package_dir.resolve()
    metadata_path = package_dir / "motion_package.json"
    if not metadata_path.exists():
        raise SystemExit(f"missing metadata: {metadata_path}")
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    arrays = metadata.get("arrays", {})
    positions = np.load(package_dir / arrays["source_positions"], allow_pickle=False)
    rotations = np.load(package_dir / arrays["target_rotations"], allow_pickle=False)
    root_motion = np.load(package_dir / arrays["root_motion"], allow_pickle=False)
    contacts = np.load(package_dir / arrays["foot_contacts"], allow_pickle=False)

    frame_count = int(metadata["frame_count"])
    bone_count = int(metadata["bone_count"])
    if positions.shape != (frame_count, 22, 3):
        raise SystemExit(f"bad source_positions shape: {positions.shape}")
    if rotations.shape != (frame_count, bone_count, 4):
        raise SystemExit(f"bad target_rotations shape: {rotations.shape}")
    if root_motion.shape != (frame_count, 3):
        raise SystemExit(f"bad root_motion shape: {root_motion.shape}")
    if contacts.shape != (frame_count, 2):
        raise SystemExit(f"bad foot_contacts shape: {contacts.shape}")
    if not np.isfinite(positions).all() or not np.isfinite(rotations).all() or not np.isfinite(root_motion).all():
        raise SystemExit("package contains NaN or infinity")
    max_quat_error = float(np.max(np.abs(np.linalg.norm(rotations, axis=2) - 1.0)))
    if max_quat_error > 1e-3:
        raise SystemExit(f"quaternions are not normalized: max error {max_quat_error}")
    if metadata.get("runtime_contract", {}).get("quaternion_order") != "wxyz":
        raise SystemExit("missing quaternion_order=wxyz runtime contract")
    print(f"RETARGET_PACKAGE_VALID id={metadata['motion_id']} frames={frame_count} bones={bone_count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
