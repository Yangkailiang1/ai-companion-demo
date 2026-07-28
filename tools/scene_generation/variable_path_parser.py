"""Variable field path parser for scene recipes.

Roadmap: S4.1
Responsibility: Parse variable field paths like 'object_slots[sofa].position'
into typed dicts. Raises SceneContractError for unrecognized formats.
Tests: tests/scene_generation/test_compile_scene_recipe.py
"""

# Verifies: S4.1

import re
from typing import Any

from tools.scene_generation.scene_contract_error import SceneContractError


def _fail(msg: str) -> None:
    raise SceneContractError(msg)


def parse_variable_path(
    path: str, prefix: str, slot_by_semantic: dict, waypoints: dict
) -> dict:
    """[S4.1] Parse a variable field path like 'object_slots[sofa].position'.

    Returns a dict with 'type', 'target', and optional 'field'.
    Raises SceneContractError for unrecognized formats.

    Side effects: None (pure parse).
    """
    result: dict[str, Any] = {"type": "", "target": ""}

    # seed
    if path == "seed":
        result["type"] = "seed"
        result["target"] = "seed"
        return result

    # object_slots[semantic_id].field
    slot_match = re.match(r"^object_slots\[([^\]]+)\]\.?(.*)$", path)
    if slot_match:
        result["type"] = "object_slot"
        result["target"] = slot_match.group(1)
        field = slot_match.group(2)
        if field:
            result["field"] = field
        return result

    # waypoints[waypoint_name] or waypoints[waypoint_name].field
    wp_match = re.match(r"^waypoints\[([^\]]+)\]\.?(.*)$", path)
    if wp_match:
        result["type"] = "waypoint"
        result["target"] = wp_match.group(1)
        field = wp_match.group(2)
        if field:
            result["field"] = field
        return result

    # openings[opening_id].field
    op_match = re.match(r"^openings\[([^\]]+)\]\.?(.*)$", path)
    if op_match:
        result["type"] = "opening"
        result["target"] = op_match.group(1)
        field = op_match.group(2)
        if field:
            result["field"] = field
        return result

    # room.*
    room_match = re.match(r"^room\.(.+)$", path)
    if room_match:
        result["type"] = "room_dimension"
        result["target"] = "room"
        result["field"] = room_match.group(1)
        return result

    # Reject unrecognized path formats (not warn)
    _fail(
        f"{prefix}: unrecognized variable field path format: '{path}'. "
        f"Forward compatibility requires a new schema version."
    )
    return result
