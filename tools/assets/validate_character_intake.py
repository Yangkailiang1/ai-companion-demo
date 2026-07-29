"""Character intake validator CLI.

Roadmap: O2.2
Responsibility: Validate character_intake.json files against the O2.2 contract;
reads and checks files but never modifies them.
"""

import argparse
import json
import os
import re
import sys

# ── constants ──────────────────────────────────────────────────────────────

ALLOWED_TOP_KEYS = frozenset({
    "schema_version", "character_id", "classification", "status",
    "model_path", "provenance_path", "inventories", "source_sha256", "notes",
})

ALLOWED_INVENTORY_KEYS = frozenset({"bones", "morphs", "animations"})

CLASSIFICATIONS = frozenset({"public_redistributable", "local_only", "rejected"})
STATUSES = frozenset({"downloaded", "inventoried", "metadata_candidate", "quarantined", "rejected"})


# ── helpers ────────────────────────────────────────────────────────────────

def _resolve_path(res_value: str, project_root: str) -> str:
    """[O2.2] Resolve a res:// path; side effects: resolves filesystem symlinks."""
    if not res_value.startswith("res://"):
        return ""  # caller handles the error message
    rel = res_value[6:]  # strip "res://"
    if not rel:
        return ""
    return os.path.realpath(os.path.join(os.path.realpath(project_root), rel))


def _check_res_safety(res_value: str) -> str | None:
    """[O2.2] Check lexical res:// safety; side effects: none."""
    if not res_value.startswith("res://"):
        return f"path must start with res://, got: {res_value}"
    rel = res_value[6:]
    if not rel:
        return f"res:// path has empty path component: {res_value}"
    if "\\" in rel:
        return f"backslash path separators rejected: {res_value}"
    if ".." in rel.split("/"):
        return f"path traversal rejected: {res_value}"
    return None


# ── validation ─────────────────────────────────────────────────────────────

def validate_intake(intake_path: str, project_root: str) -> list[str]:
    """[O2.2] Validate one character_intake.json.

    Returns a list of error strings; empty if valid.
    Side effects: reads referenced files and resolves symlinks.
    """
    errors: list[str] = []

    # 0. parse
    try:
        with open(intake_path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except FileNotFoundError:
        return [f"intake file not found: {intake_path}"]
    except json.JSONDecodeError as exc:
        return [f"invalid JSON in {intake_path}: {exc}"]

    if not isinstance(data, dict):
        return [f"intake root must be a JSON object, got {type(data).__name__}"]

    # 0.1 unknown fields
    extra = set(data.keys()) - ALLOWED_TOP_KEYS
    if extra:
        errors.append(f"unknown top-level keys: {sorted(extra)}")

    # 1. schema_version
    sv = data.get("schema_version")
    if not isinstance(sv, int):
        errors.append(f"schema_version must be an integer, got {type(sv).__name__}")
    elif sv != 1:
        errors.append(f"schema_version must be exactly 1, got {sv}")

    # 2. character_id
    cid = data.get("character_id")
    if not isinstance(cid, str):
        errors.append(f"character_id must be a string, got {type(cid).__name__}")
    elif not re.fullmatch(r"^[a-z][a-z0-9_]*$", cid):
        errors.append(f"character_id must be lower snake_case, got: {cid}")

    # 3. classification
    cls_val = data.get("classification")
    if cls_val not in CLASSIFICATIONS:
        errors.append(f"classification must be one of {sorted(CLASSIFICATIONS)}, got: {cls_val}")

    # 4. status
    stat_val = data.get("status")
    if stat_val not in STATUSES:
        errors.append(f"status must be one of {sorted(STATUSES)}, got: {stat_val}")

    # 5. model_path
    mp = data.get("model_path")
    if not isinstance(mp, str):
        errors.append(f"model_path must be a string, got {type(mp).__name__}")
    else:
        err = _check_res_safety(mp)
        if err:
            errors.append(f"model_path: {err}")

    # 6. provenance_path
    pp = data.get("provenance_path")
    if not isinstance(pp, str):
        errors.append(f"provenance_path must be a string, got {type(pp).__name__}")
    else:
        err = _check_res_safety(pp)
        if err:
            errors.append(f"provenance_path: {err}")

    # 7. source_sha256
    sha = data.get("source_sha256")
    if not isinstance(sha, str):
        errors.append(f"source_sha256 must be a string, got {type(sha).__name__}")
    elif not re.fullmatch(r"^[a-f0-9]{64}$", sha):
        errors.append(f"source_sha256 must be 64 lowercase hex chars, got: {sha}")

    # 8. inventories
    inv = data.get("inventories")
    if not isinstance(inv, dict):
        errors.append(f"inventories must be an object, got {type(inv).__name__}")
    else:
        inv_extra = set(inv.keys()) - ALLOWED_INVENTORY_KEYS
        if inv_extra:
            errors.append(f"unknown inventory keys: {sorted(inv_extra)}")
        for key in ("bones", "morphs", "animations"):
            val = inv.get(key)
            if not isinstance(val, str):
                errors.append(f"inventories.{key} must be a string, got {type(val).__name__}")
            else:
                err = _check_res_safety(val)
                if err:
                    errors.append(f"inventories.{key}: {err}")

    # 9. notes (optional)
    notes = data.get("notes")
    if notes is not None:
        if not isinstance(notes, list):
            errors.append(f"notes must be an array, got {type(notes).__name__}")
        else:
            for i, note in enumerate(notes):
                if not isinstance(note, str) or len(note) == 0:
                    errors.append(f"notes[{i}] must be a non-empty string")

    # 10. notes about 'accepted' status
    # The schema doesn't list 'accepted' as a valid status, so it's rejected at the enum check above.

    # If early errors in required fields, skip file-access checks
    if not isinstance(mp, str) or not isinstance(pp, str) or not isinstance(inv, dict) or not isinstance(sha, str):
        return errors

    # ── cross-field & file-existence checks ────────────────────────────────

    # Resolve all res:// paths
    paths_to_check = [
        ("model_path", mp),
        ("provenance_path", pp),
    ]
    for key in ("bones", "morphs", "animations"):
        if isinstance(inv.get(key), str):
            paths_to_check.append((f"inventories.{key}", inv[key]))

    for label, res_val in paths_to_check:
        if _check_res_safety(res_val):
            continue  # already reported above
        fs_path = _resolve_path(res_val, project_root)
        abs_pr = os.path.realpath(project_root)
        if not fs_path.startswith(abs_pr + os.sep) and fs_path != abs_pr:
            errors.append(f"{label}: resolved path {fs_path} escapes project root {abs_pr}")
        elif not os.path.isfile(fs_path):
            errors.append(f"{label}: file not found: {fs_path}")

    if errors:
        return errors

    # Load and validate provenance
    prov_path = _resolve_path(pp, project_root)
    try:
        with open(prov_path, "r", encoding="utf-8") as fh:
            prov = json.load(fh)
    except Exception as exc:
        errors.append(f"provenance_path: cannot parse JSON: {exc}")
        return errors

    if not isinstance(prov, dict):
        errors.append("provenance must be a JSON object")
        return errors

    # SHA match
    prov_sha = prov.get("source_sha256")
    if sha != prov_sha:
        errors.append(f"source_sha256 mismatch: intake has {sha}, provenance has {prov_sha}")

    # All referenced inventory JSON must parse, including rejected packages.
    for key in ("bones", "morphs", "animations"):
        fs_path = _resolve_path(inv[key], project_root)
        try:
            with open(fs_path, "r", encoding="utf-8") as fh:
                json.load(fh)
        except Exception as exc:
            errors.append(f"inventories.{key}: {exc}")

    # Cross-field classification rules.
    if cls_val != "rejected" and stat_val == "rejected":
        errors.append(
            f"classification={cls_val} must not use status=rejected"
        )

    if cls_val == "rejected":
        if stat_val != "rejected":
            errors.append(
                f"classification=rejected requires status=rejected, got status={stat_val}"
            )
        return errors

    prov_redist = prov.get("redistribution", "")
    prov_license = prov.get("license", "")

    if cls_val == "public_redistributable":
        if prov_redist != "allowed":
            errors.append(
                f"classification=public_redistributable requires provenance redistribution=allowed, "
                f"got {prov_redist}"
            )
        if not prov_license or prov_license == "unknown":
            errors.append(
                f"classification=public_redistributable requires non-empty, non-unknown license; "
                f"got: {prov_license!r}"
            )
    elif cls_val == "local_only":
        if prov_redist != "local_only":
            errors.append(
                f"classification=local_only requires provenance redistribution=local_only, "
                f"got {prov_redist}"
            )

    return errors


# ── CLI ────────────────────────────────────────────────────────────────────

def main() -> None:
    """[O2.2] Run CLI; side effects: reads files, prints output, exits process."""
    parser = argparse.ArgumentParser(
        description="Validate character_intake.json files."
    )
    parser.add_argument(
        "intake_files", nargs="+",
        help="One or more character_intake.json paths",
    )
    parser.add_argument(
        "--project-root", default=".",
        help="Project root for resolving res:// paths (default: .)",
    )
    args = parser.parse_args()

    pr = os.path.abspath(args.project_root)
    if not os.path.isdir(pr):
        print(f"ERROR: --project-root is not a directory: {pr}", file=sys.stderr)
        sys.exit(1)

    all_errors: list[str] = []
    for path in args.intake_files:
        errs = validate_intake(path, pr)
        if errs:
            for e in errs:
                all_errors.append(f"{path}: {e}")

    if all_errors:
        for e in all_errors:
            print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    print("CHARACTER_INTAKE_PASS")
    sys.exit(0)


if __name__ == "__main__":
    main()
