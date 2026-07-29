"""Create per-character expression channel_maps for local PMX-derived characters.

Roadmap: C3.1, C6.1
Side effects: Writes candidate expression_adapter.json per local character.
"""
from __future__ import annotations

import json
import os
import pathlib
import sys

PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[2]
LOCAL_CHARS = ["cartethyia", "castorice", "xiangliyao"]

# Shared semantic expression targets
SEMANTIC_MAP = {
    "neutral": {"type": "native", "channel": ["neutral", "真面目", "通常"]},
    "joy": {"type": "native", "channel": ["にこり", "喜び", "笑い", "楽", "なごみ"]},
    "angry": {"type": "native", "channel": ["怒り"]},
    "sad": {"type": "approximate", "channel": ["悲しい", "困る", "困った", "涙"]},
    "surprised": {"type": "native", "channel": ["びっくり", "驚き"]},
    "blink": {"type": "native", "channel": ["まばたき", "ウィンク"]},
    "a": {"type": "native", "channel": ["あ"]},
    "i": {"type": "native", "channel": ["い"]},
    "u": {"type": "native", "channel": ["う"]},
    "e": {"type": "native", "channel": ["え"]},
    "o": {"type": "native", "channel": ["お"]},
    "shy": {"type": "approximate", "channel": ["じと目", "はぅ", "ω"]},
    "bored": {"type": "approximate", "channel": ["じと目", "下"]},
    "confused": {"type": "approximate", "channel": ["困る", "困った", "真面目"]},
}


def load_reference_expression_adapter(char_id: str) -> dict | None:
    """Load one character's current runtime expression adapter.

    Roadmap: C3.1, C6.1
    Returns the expression_adapter dict, or None if not found.
    """
    manifest_path = (
        PROJECT_ROOT / "assets" / "local_characters"
        / char_id / "character_manifest.json"
    )
    if not manifest_path.exists():
        return None
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        return manifest.get("adapter", {}).get("expression_adapter")
    except (OSError, json.JSONDecodeError):
        return None


def match_morphs(morph_names: set[str], reference_adapter: dict | None) -> dict:
    """Build a candidate without dropping verified runtime aliases.

    Roadmap: C3.1, C6.1
    Side effects: None.
    """
    channel_map = {}
    reference_channels = (
        reference_adapter.get("channel_map", {}) if reference_adapter else {}
    )
    for semantic_id, spec in SEMANTIC_MAP.items():
        reference_aliases = reference_channels.get(semantic_id, [])
        found = [
            alias for alias in dict.fromkeys([*reference_aliases, *spec["channel"]])
            if alias in morph_names
        ]
        if found:
            channel_map[semantic_id] = {
                "type": (
                    "existing_runtime"
                    if any(alias in reference_aliases for alias in found)
                    else spec["type"]
                ),
                "morphs": found,
                "primary": found[0],
            }
        else:
            channel_map[semantic_id] = {
                "type": "unsupported",
                "morphs": [],
                "primary": "",
            }
    return channel_map


def check_non_regression(char_id: str, candidate_channel: dict, reference_adapter: dict | None) -> list[str]:
    """Compare candidate channel_map against existing runtime manifest.

    Roadmap: C3.1, C6.1
    Returns a list of warning messages for regressions (e.g., a semantic that
    was already mapped in runtime but would become unsupported in the candidate).
    """
    warnings = []
    if reference_adapter is None:
        return warnings

    ref_channel = reference_adapter.get("channel_map", {})
    for semantic_id in ref_channel:
        ref_morphs = ref_channel[semantic_id]
        if not ref_morphs:
            continue  # empty = nothing to regress on
        candidate = candidate_channel.get(semantic_id, {})
        if candidate.get("type") == "unsupported":
            warnings.append(
                f"  ⚠ REGRESSION: {char_id} candidate marks '{semantic_id}' as unsupported, "
                f"but runtime manifest already maps it to {ref_morphs}"
            )
    return warnings


def main() -> int:
    """Generate local-only candidates and report runtime regressions.

    Roadmap: C3.1, C6.1
    Side effects: Writes ignored candidate metadata only.
    """

    print("=== Expression Channel Map Candidate Batch ===")
    print("  NOTE: Outputs are CANDIDATES only. Runtime reads character_manifest.json,")
    print("  NOT standalone expression_adapter.json.")
    print()

    for char_id in LOCAL_CHARS:
        ref_adapter = load_reference_expression_adapter(char_id)
        morph_path = PROJECT_ROOT / "assets" / "local_characters" / char_id / "morph_inventory.json"
        if not morph_path.exists():
            print(f"  ✗ {char_id}: no morph inventory")
            continue

        morph_data = json.loads(morph_path.read_text(encoding="utf-8"))
        # Get unique morph names across all meshes
        morph_names = set(m["name"] for m in morph_data.get("morphs", []))

        channel = match_morphs(morph_names, ref_adapter)
        supported = sum(1 for v in channel.values() if v["type"] != "unsupported")
        total = len(channel)

        # Non-regression check against runtime manifest
        regressions = check_non_regression(char_id, channel, ref_adapter)
        for w in regressions:
            print(w)

        adapter = {
            "schema_version": 1,
            "character_id": char_id,
            "type": "blend_shapes",
            "status": "candidate",
            "status_note": "NOT connected to Runtime. Runtime reads character_manifest.json adapter.expression_adapter, not this standalone file. Must complete mesh weight test, neutral reset, and Metal screenshot review before accepted.",
            "morph_count": len(morph_names),
            "coverage": f"{supported}/{total}",
            "has_runtime_regressions": len(regressions) > 0,
            "channel_map": channel,
            "channel_map_patch": {
                semantic_id: record["morphs"]
                for semantic_id, record in channel.items()
                if record["type"] != "unsupported"
            },
        }

        out_path = (
            PROJECT_ROOT / "assets" / "local_characters" / char_id
            / "expression_adapter.candidate.json"
        )
        out_path.write_text(json.dumps(adapter, indent=2, ensure_ascii=False) + os.linesep, encoding="utf-8")

        print(f"  ✓ {char_id}: coverage={adapter['coverage']} morphs={adapter['morph_count']} regressions={len(regressions)}")

    print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
