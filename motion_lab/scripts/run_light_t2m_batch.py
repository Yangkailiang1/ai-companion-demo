#!/usr/bin/env python3
"""Invoke the official Light-T2M sampler for validated JSONL requests on a GPU server."""

from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("requests", type=pathlib.Path)
    parser.add_argument("--lab-root", type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[1])
    parser.add_argument("--device", default="0")
    args = parser.parse_args()

    lab_root = args.lab_root.resolve()
    upstream = lab_root / "vendor" / "light-t2m"
    checkpoint = lab_root / "checkpoints" / "hml3d.ckpt"
    data_dir = lab_root / "datasets" / "HumanML3D"
    output_dir = lab_root / "generated"
    required = [upstream / "src" / "sample_motion.py", checkpoint, data_dir / "Mean.npy", data_dir / "Std.npy"]
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise SystemExit("missing Light-T2M runtime files:\n" + "\n".join(missing))

    records = [json.loads(line) for line in args.requests.read_text(encoding="utf-8").splitlines() if line.strip()]
    output_dir.mkdir(parents=True, exist_ok=True)
    for record in records:
        request_id = str(record["request_id"])
        command = [
            sys.executable,
            str(upstream / "src" / "sample_motion.py"),
            f"device={args.device}",
            f"ckpt_path={checkpoint}",
            f"data_dir={data_dir}",
            f"save_path={output_dir}",
            f"text={record['text']}",
            f"length={int(record['length_frames'])}",
            f"seed={int(record['seed'])}",
            f"sample_name={request_id}",
            "repeats=1",
        ]
        subprocess.run(command, cwd=upstream, check=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
