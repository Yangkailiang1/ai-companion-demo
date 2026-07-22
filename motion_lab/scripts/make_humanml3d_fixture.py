#!/usr/bin/env python3
"""Create a tiny HumanML3D-style 22-joint motion for retargeting smoke tests."""

from __future__ import annotations

import argparse
import pathlib

import numpy as np


REST = np.array(
    [
        [0.0, 0.95, 0.0],  # pelvis
        [-0.12, 0.85, 0.0],
        [0.12, 0.85, 0.0],
        [0.0, 1.12, 0.0],
        [-0.16, 0.52, 0.0],
        [0.16, 0.52, 0.0],
        [0.0, 1.32, 0.0],
        [-0.16, 0.18, 0.02],
        [0.16, 0.18, 0.02],
        [0.0, 1.5, 0.0],
        [-0.16, 0.08, 0.18],
        [0.16, 0.08, 0.18],
        [0.0, 1.62, 0.0],
        [-0.16, 1.48, 0.0],
        [0.16, 1.48, 0.0],
        [0.0, 1.82, 0.0],
        [-0.42, 1.42, 0.0],
        [0.42, 1.42, 0.0],
        [-0.62, 1.15, 0.0],
        [0.62, 1.15, 0.0],
        [-0.72, 0.92, 0.02],
        [0.72, 0.92, 0.02],
    ],
    dtype=np.float32,
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("--frames", type=int, default=72)
    args = parser.parse_args()

    frames = max(args.frames, 20)
    motion = np.repeat(REST[None, :, :], frames, axis=0)
    for frame in range(frames):
        phase = frame / float(frames - 1) * 2.0 * np.pi
        root_forward = frame / float(frames - 1) * 0.8
        bob = np.sin(phase * 2.0) * 0.025
        arm = np.sin(phase) * 0.24
        leg = np.sin(phase) * 0.16

        motion[frame, :, 2] += root_forward
        motion[frame, :, 1] += bob
        motion[frame, 18, 2] += arm
        motion[frame, 20, 2] += arm * 1.2
        motion[frame, 19, 2] -= arm
        motion[frame, 21, 2] -= arm * 1.2
        motion[frame, 4, 2] -= leg
        motion[frame, 7, 2] -= leg * 1.2
        motion[frame, 5, 2] += leg
        motion[frame, 8, 2] += leg * 1.2

    args.output.parent.mkdir(parents=True, exist_ok=True)
    np.save(args.output, motion.astype(np.float32), allow_pickle=False)
    print(f"HUMANML3D_FIXTURE path={args.output} shape={motion.shape}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
