#!/usr/bin/env python3
"""Validate canonical joint positions emitted by Light-T2M before retargeting."""

from __future__ import annotations

import argparse
import pathlib

import numpy as np


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("motion", type=pathlib.Path)
    parser.add_argument("--min-frames", type=int, default=20)
    parser.add_argument("--max-frames", type=int, default=196)
    args = parser.parse_args()

    motion = np.load(args.motion, allow_pickle=False)
    if motion.ndim != 3 or motion.shape[1:] != (22, 3):
        raise SystemExit(f"invalid shape {motion.shape}; expected (T, 22, 3)")
    if not args.min_frames <= motion.shape[0] <= args.max_frames:
        raise SystemExit(f"invalid frame count {motion.shape[0]}")
    if not np.isfinite(motion).all():
        raise SystemExit("motion contains NaN or infinity")
    if float(np.max(np.abs(motion))) > 100.0:
        raise SystemExit("motion exceeds the canonical safety bounds")
    print(f"MOTION_VALID frames={motion.shape[0]} joints=22 dtype={motion.dtype}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
