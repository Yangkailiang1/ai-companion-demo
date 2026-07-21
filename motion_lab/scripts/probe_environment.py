#!/usr/bin/env python3
"""Report whether this machine can run the official Light-T2M stack."""

from __future__ import annotations

import importlib.util
import pathlib
import platform
import shutil


def main() -> int:
    root = pathlib.Path(__file__).resolve().parents[1]
    vendor = root / "vendor" / "light-t2m"
    checkpoint = root / "checkpoints" / "hml3d.ckpt"
    facts = {
        "platform": platform.system(),
        "machine": platform.machine(),
        "official_source_present": vendor.is_dir(),
        "checkpoint_present": checkpoint.is_file(),
        "torch_present": importlib.util.find_spec("torch") is not None,
        "nvcc_present": shutil.which("nvcc") is not None,
    }
    supported = (
        facts["platform"] == "Linux"
        and facts["machine"] in {"x86_64", "AMD64"}
        and facts["official_source_present"]
        and facts["checkpoint_present"]
        and facts["torch_present"]
        and facts["nvcc_present"]
    )
    print("LIGHT_T2M_ENVIRONMENT")
    for name, value in facts.items():
        print(f"{name}={value}")
    print(f"official_inference_ready={supported}")
    if not supported:
        print("reason=official Mamba extension targets Linux x86_64 with CUDA; use the GPU server workflow")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
