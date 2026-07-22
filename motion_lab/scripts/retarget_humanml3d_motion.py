#!/usr/bin/env python3
"""Convert canonical HumanML3D 22-joint positions into a reusable retarget package.

The output is deliberately model-adapter friendly: it stores target bone names,
per-frame local rotation deltas, separated root motion, and quality metadata. A later
Blender/Godot baker can apply the same package to any character with a compatible
bone map and rest-pose profile.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import pathlib
from dataclasses import dataclass
from typing import Iterable

import numpy as np


HML_PARENT = {
    0: -1,
    1: 0,
    2: 0,
    3: 0,
    4: 1,
    5: 2,
    6: 3,
    7: 4,
    8: 5,
    9: 6,
    10: 7,
    11: 8,
    12: 9,
    13: 9,
    14: 9,
    15: 12,
    16: 13,
    17: 14,
    18: 16,
    19: 17,
    20: 18,
    21: 19,
}

PRIMARY_CHILD = {
    0: 3,
    1: 4,
    2: 5,
    3: 6,
    4: 7,
    5: 8,
    6: 9,
    7: 10,
    8: 11,
    9: 12,
    10: None,
    11: None,
    12: 15,
    13: 16,
    14: 17,
    15: None,
    16: 18,
    17: 19,
    18: 20,
    19: 21,
    20: None,
    21: None,
}

GODOT_COORDINATE_NOTE = "source is converted as x=source_x, y=source_y, z=source_z; root translation is separated"


@dataclass(frozen=True)
class BoneTrack:
    source_index: int
    source_name: str
    target_name: str
    child_index: int | None
    approximate: bool
    mapping_mode: str


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("motion", type=pathlib.Path, help="HumanML3D/Light-T2M joint positions, shape (T,22,3)")
    parser.add_argument("--bone-map", type=pathlib.Path, default=pathlib.Path("data/humanml3d_penguin_bone_map.json"))
    parser.add_argument("--output-dir", type=pathlib.Path, default=pathlib.Path("motion_lab/generated/library"))
    parser.add_argument("--motion-id", default="")
    parser.add_argument("--text", default="")
    parser.add_argument("--fps", type=float, default=20.0)
    parser.add_argument("--root-mode", choices=["in_place", "keep"], default="in_place")
    args = parser.parse_args()

    motion_path = args.motion.resolve()
    motion = np.load(motion_path, allow_pickle=False).astype(np.float32)
    validate_motion(motion)

    bone_map = load_bone_map(args.bone_map)
    tracks = build_tracks(bone_map)
    motion_id = args.motion_id or motion_path.stem
    package_dir = args.output_dir / safe_id(motion_id)
    package_dir.mkdir(parents=True, exist_ok=True)

    source_positions = convert_to_godot_coordinates(motion)
    root_motion = source_positions[:, 0, :].copy()
    in_place_positions = source_positions.copy()
    if args.root_mode == "in_place":
        in_place_positions[:, :, 0] -= root_motion[:, 0:1]
        in_place_positions[:, :, 2] -= root_motion[:, 2:3]

    rotations = build_rotation_tracks(in_place_positions, tracks)
    foot_contacts = estimate_foot_contacts(source_positions)
    quality = summarize_quality(source_positions, tracks, rotations, foot_contacts)

    np.save(package_dir / "source_positions.npy", in_place_positions.astype(np.float32), allow_pickle=False)
    np.save(package_dir / "target_rotations.npy", rotations.astype(np.float32), allow_pickle=False)
    np.save(package_dir / "root_motion.npy", root_motion.astype(np.float32), allow_pickle=False)
    np.save(package_dir / "foot_contacts.npy", foot_contacts.astype(np.bool_), allow_pickle=False)

    metadata = {
        "version": 1,
        "motion_id": safe_id(motion_id),
        "source_path": str(motion_path),
        "source_sha256": sha256_file(motion_path),
        "source_format": "HumanML3D canonical joint positions",
        "coordinate_note": GODOT_COORDINATE_NOTE,
        "fps": args.fps,
        "frame_count": int(source_positions.shape[0]),
        "joint_count": 22,
        "root_mode": args.root_mode,
        "text": args.text,
        "target_skeleton": bone_map.get("target_skeleton", ""),
        "bone_count": len(tracks),
        "bone_tracks": [track.__dict__ for track in tracks],
        "arrays": {
            "source_positions": "source_positions.npy",
            "target_rotations": "target_rotations.npy",
            "root_motion": "root_motion.npy",
            "foot_contacts": "foot_contacts.npy",
        },
        "quality": quality,
        "runtime_contract": {
            "target_rotations_shape": [int(rotations.shape[0]), int(rotations.shape[1]), 4],
            "quaternion_order": "wxyz",
            "bone_name_order": [track.target_name for track in tracks],
            "root_motion_is_world_delta_source": args.root_mode == "in_place",
        },
    }
    (package_dir / "motion_package.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"RETARGET_PACKAGE path={package_dir} frames={source_positions.shape[0]} bones={len(tracks)}")
    return 0


def validate_motion(motion: np.ndarray) -> None:
    if motion.ndim != 3 or motion.shape[1:] != (22, 3):
        raise SystemExit(f"invalid shape {motion.shape}; expected (T,22,3)")
    if motion.shape[0] < 20:
        raise SystemExit(f"motion is too short: {motion.shape[0]} frames")
    if not np.isfinite(motion).all():
        raise SystemExit("motion contains NaN or infinity")
    if float(np.max(np.abs(motion))) > 100.0:
        raise SystemExit("motion exceeds safety bounds")


def load_bone_map(path: pathlib.Path) -> dict:
    parsed = json.loads(path.read_text(encoding="utf-8"))
    joints = parsed.get("joints", [])
    if len(joints) != 22:
        raise SystemExit("bone map must contain exactly 22 HumanML3D joints")
    return parsed


def build_tracks(bone_map: dict) -> list[BoneTrack]:
    tracks: list[BoneTrack] = []
    seen: set[str] = set()
    for entry in bone_map["joints"]:
        target = str(entry["target"])
        source_index = int(entry["index"])
        child_index = PRIMARY_CHILD.get(source_index)
        if child_index is None:
            continue
        key = f"{target}:{source_index}:{child_index}"
        if key in seen:
            continue
        seen.add(key)
        tracks.append(
            BoneTrack(
                source_index=source_index,
                source_name=str(entry["source"]),
                target_name=target,
                child_index=child_index,
                approximate=bool(entry.get("approximate", False)),
                mapping_mode=str(entry.get("mapping_mode", "direction_delta")),
            )
        )
    return tracks


def convert_to_godot_coordinates(motion: np.ndarray) -> np.ndarray:
    return motion.copy()


def build_rotation_tracks(positions: np.ndarray, tracks: Iterable[BoneTrack]) -> np.ndarray:
    track_list = list(tracks)
    rotations = np.zeros((positions.shape[0], len(track_list), 4), dtype=np.float32)
    rest_vectors = []
    for track in track_list:
        assert track.child_index is not None
        rest_vectors.append(safe_normalize(positions[0, track.child_index] - positions[0, track.source_index]))
    for frame in range(positions.shape[0]):
        for track_index, track in enumerate(track_list):
            assert track.child_index is not None
            current = safe_normalize(positions[frame, track.child_index] - positions[frame, track.source_index])
            rotations[frame, track_index] = quaternion_between(rest_vectors[track_index], current)
    return smooth_quaternion_signs(rotations)


def estimate_foot_contacts(positions: np.ndarray) -> np.ndarray:
    feet = [10, 11]
    contact = np.zeros((positions.shape[0], len(feet)), dtype=np.bool_)
    for foot_i, joint_i in enumerate(feet):
        height = positions[:, joint_i, 1]
        speed = np.zeros(positions.shape[0], dtype=np.float32)
        speed[1:] = np.linalg.norm(np.diff(positions[:, joint_i, :], axis=0), axis=1)
        low = height <= np.percentile(height, 35)
        still = speed <= max(float(np.percentile(speed, 45)), 1e-4)
        contact[:, foot_i] = np.logical_and(low, still)
    return contact


def summarize_quality(positions: np.ndarray, tracks: list[BoneTrack], rotations: np.ndarray, foot_contacts: np.ndarray) -> dict:
    bone_lengths = []
    for track in tracks:
        assert track.child_index is not None
        lengths = np.linalg.norm(positions[:, track.child_index] - positions[:, track.source_index], axis=1)
        bone_lengths.append(
            {
                "target": track.target_name,
                "source": track.source_name,
                "mean": float(np.mean(lengths)),
                "std": float(np.std(lengths)),
                "relative_std": float(np.std(lengths) / max(np.mean(lengths), 1e-6)),
            }
        )
    quat_norm_error = np.abs(np.linalg.norm(rotations, axis=2) - 1.0)
    return {
        "max_abs_position": float(np.max(np.abs(positions))),
        "max_quaternion_norm_error": float(np.max(quat_norm_error)),
        "foot_contact_ratio_left": float(np.mean(foot_contacts[:, 0])),
        "foot_contact_ratio_right": float(np.mean(foot_contacts[:, 1])),
        "bone_lengths": bone_lengths,
    }


def quaternion_between(v0: np.ndarray, v1: np.ndarray) -> np.ndarray:
    v0 = safe_normalize(v0)
    v1 = safe_normalize(v1)
    dot = float(np.clip(np.dot(v0, v1), -1.0, 1.0))
    if dot > 0.999999:
        return np.array([1.0, 0.0, 0.0, 0.0], dtype=np.float32)
    if dot < -0.999999:
        axis = safe_normalize(np.cross(v0, np.array([1.0, 0.0, 0.0], dtype=np.float32)))
        if np.linalg.norm(axis) < 1e-5:
            axis = safe_normalize(np.cross(v0, np.array([0.0, 1.0, 0.0], dtype=np.float32)))
        return np.array([0.0, axis[0], axis[1], axis[2]], dtype=np.float32)
    axis = np.cross(v0, v1)
    quat = np.array([1.0 + dot, axis[0], axis[1], axis[2]], dtype=np.float32)
    return safe_normalize_quat(quat)


def safe_normalize(vector: np.ndarray) -> np.ndarray:
    norm = float(np.linalg.norm(vector))
    if norm < 1e-8:
        return np.array([0.0, 1.0, 0.0], dtype=np.float32)
    return (vector / norm).astype(np.float32)


def safe_normalize_quat(quat: np.ndarray) -> np.ndarray:
    norm = math.sqrt(float(np.dot(quat, quat)))
    if norm < 1e-8:
        return np.array([1.0, 0.0, 0.0, 0.0], dtype=np.float32)
    return (quat / norm).astype(np.float32)


def smooth_quaternion_signs(rotations: np.ndarray) -> np.ndarray:
    smoothed = rotations.copy()
    for track in range(smoothed.shape[1]):
        for frame in range(1, smoothed.shape[0]):
            if float(np.dot(smoothed[frame - 1, track], smoothed[frame, track])) < 0.0:
                smoothed[frame, track] *= -1.0
    return smoothed


def safe_id(value: str) -> str:
    cleaned = "".join(ch if ch.isalnum() or ch in "-_" else "_" for ch in value.strip().lower())
    return cleaned or "motion"


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


if __name__ == "__main__":
    raise SystemExit(main())
