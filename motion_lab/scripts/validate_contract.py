#!/usr/bin/env python3
"""Validate motion request JSONL without importing Light-T2M or GPU libraries."""

from __future__ import annotations

import json
import pathlib
import sys


REQUIRED = {
    "request_id": str,
    "text": str,
    "length_frames": int,
    "fps": int,
    "style": str,
    "seed": int,
}


def validate(path: pathlib.Path) -> int:
    errors: list[str] = []
    request_ids: set[str] = set()
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not raw.strip():
            continue
        try:
            record = json.loads(raw)
        except json.JSONDecodeError as exc:
            errors.append(f"line {line_number}: invalid JSON: {exc}")
            continue
        for name, expected_type in REQUIRED.items():
            if not isinstance(record.get(name), expected_type):
                errors.append(f"line {line_number}: {name} must be {expected_type.__name__}")
        request_id = record.get("request_id")
        if request_id in request_ids:
            errors.append(f"line {line_number}: duplicate request_id {request_id}")
        request_ids.add(request_id)
        if not 20 <= record.get("length_frames", 0) <= 196:
            errors.append(f"line {line_number}: length_frames must be between 20 and 196")
        if record.get("fps") not in {20, 30}:
            errors.append(f"line {line_number}: fps must be 20 or 30")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"CONTRACT_VALID records={len(request_ids)}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: validate_contract.py REQUESTS.jsonl")
    raise SystemExit(validate(pathlib.Path(sys.argv[1])))
