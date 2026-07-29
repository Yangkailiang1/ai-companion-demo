"""Scene recipe and asset registry validators with cross-reference checks.

Roadmap: S4.1
Responsibility: Validate recipe and registry structures, IDs, cross-references,
anchors and variable fields. Never modifies Godot world state or scene files.
Tests: tests/scene_generation/test_compile_scene_recipe.py
"""

# Verifies: S4.1

import re
from typing import Any

from tools.scene_generation.registry_validator import validate_registry
from tools.scene_generation.scene_contract_error import SceneContractError
from tools.scene_generation.variable_path_parser import parse_variable_path

# ---------------------------------------------------------------------------
# ID / field patterns
# ---------------------------------------------------------------------------

_ID_RE = re.compile(r"^[a-z][a-z0-9_]*(?:_[a-z0-9_]+)*$")
_VERSION_RE = re.compile(r"^\d+\.\d+\.\d+$")

VALID_ANCHOR_TYPES = frozenset(
    {"object_slot", "waypoint", "room_dimension", "opening"}
)

KNOWN_RECIPE_TOP_LEVEL = frozenset(
    {
        "schema_version",
        "recipe_id",
        "recipe_version",
        "registry_id",
        "registry_version",
        "seed",
        "description",
        "room",
        "object_slots",
        "waypoints",
        "routes",
        "immutable_anchors",
        "variable_fields",
    }
)

KNOWN_SLOT_KEYS = frozenset(
    {
        "semantic_id",
        "asset_id",
        "display_name",
        "description",
        "position",
        "rotation_deg",
        "scale",
        "interaction_point",
        "needs_proximity",
        "affordances",
        "effects",
        "initial_state",
        "properties",
        "consumable",
    }
)
REQUIRED_SLOT_KEYS = frozenset(
    {
        "semantic_id",
        "asset_id",
        "display_name",
        "position",
        "interaction_point",
        "needs_proximity",
        "affordances",
    }
)
# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------


def _fail(msg: str) -> None:
    raise SceneContractError(msg)


def _validate_snake_id(value: Any, label: str) -> str:
    """[S4.1] Reject malformed IDs."""
    if not isinstance(value, str) or not _ID_RE.match(value):
        _fail(f"{label} '{value}' is not a valid snake_case ID.")
    return value


def _validate_version_str(value: Any, label: str) -> str:
    """[S4.1] Reject malformed semantic version strings."""
    if not isinstance(value, str) or not _VERSION_RE.match(value):
        _fail(f"{label} '{value}' is not a valid semantic version.")
    return value


def _check_unknown_fields(data: dict, known: frozenset, label: str) -> None:
    """[S4.1] Reject every unknown top-level field."""
    for key in data:
        if key not in known:
            _fail(f"Unknown top-level field '{key}' in {label}.")


def _check_required_keys(data: dict, required: frozenset, label: str) -> None:
    """[S4.1] Reject missing required fields."""
    for key in required:
        if key not in data:
            _fail(f"Missing required field '{key}' in {label}.")


# ---------------------------------------------------------------------------
# Recipe validation
# ---------------------------------------------------------------------------


def validate_recipe(recipe: dict, asset_map: dict) -> None:
    """[S4.1] Validate the recipe structure, cross-references, anchors and variable fields.

    Raises SceneContractError on any validation failure.
    """
    _check_unknown_fields(recipe, KNOWN_RECIPE_TOP_LEVEL, "recipe")
    _check_required_keys(
        recipe,
        frozenset(
            {
                "schema_version",
                "recipe_id",
                "recipe_version",
                "registry_id",
                "registry_version",
                "seed",
                "room",
                "object_slots",
                "waypoints",
                "immutable_anchors",
                "variable_fields",
            }
        ),
        "recipe",
    )

    _validate_snake_id(recipe["recipe_id"], "recipe.recipe_id")
    _validate_version_str(recipe["recipe_version"], "recipe.recipe_version")
    _validate_snake_id(recipe["registry_id"], "recipe.registry_id")
    _validate_version_str(recipe["registry_version"], "recipe.registry_version")

    if not isinstance(recipe["schema_version"], int) or recipe["schema_version"] < 1:
        _fail("recipe.schema_version must be a positive integer.")

    if not isinstance(recipe["seed"], int):
        _fail("recipe.seed must be an integer.")

    if not isinstance(recipe["room"], dict):
        _fail("recipe.room must be an object.")
    openings = recipe["room"].get("openings", [])
    if not isinstance(openings, list):
        _fail("recipe.room.openings must be an array.")
    occupied_walls: set[str] = set()
    for index, opening in enumerate(openings):
        if not isinstance(opening, dict):
            _fail(f"recipe.room.openings[{index}] must be an object.")
        wall_id = opening.get("wall_id", "")
        if wall_id in occupied_walls:
            _fail(
                f"recipe schema v1 supports at most one opening per wall; duplicate '{wall_id}'."
            )
        occupied_walls.add(wall_id)

    # -----------------------------------------------------------------------
    # Object slots
    # -----------------------------------------------------------------------
    slots = recipe.get("object_slots")
    if not isinstance(slots, list) or len(slots) == 0:
        _fail("recipe.object_slots must be a non-empty array.")

    seen_semantic: set[str] = set()
    slot_by_semantic: dict[str, dict] = {}

    for i, slot in enumerate(slots):
        prefix = f"recipe.object_slots[{i}]"

        if not isinstance(slot, dict):
            _fail(f"{prefix} is not an object.")

        # Reject unknown keys inside slot (not warn)
        for key in slot:
            if key not in KNOWN_SLOT_KEYS:
                _fail(f"Unknown nested field '{key}' in {prefix}.")
        _check_required_keys(slot, REQUIRED_SLOT_KEYS, prefix)

        semantic_id = slot.get("semantic_id", "")
        _validate_snake_id(semantic_id, f"{prefix}.semantic_id")

        if semantic_id in seen_semantic:
            _fail(f"Duplicate semantic_id '{semantic_id}' in object_slots.")
        seen_semantic.add(semantic_id)
        slot_by_semantic[semantic_id] = slot

        asset_id = slot.get("asset_id", "")
        _validate_snake_id(asset_id, f"{prefix}.asset_id")

        # Cross-reference: every slot asset_id must exist in the registry
        if asset_id not in asset_map:
            _fail(
                f"{prefix} references asset_id '{asset_id}' which is not in the registry."
            )

        # Validate position and interaction_point are 3-element arrays
        for field in ("position", "interaction_point"):
            val = slot.get(field)
            if not isinstance(val, list) or len(val) != 3 or not all(isinstance(v, (int, float)) for v in val):
                _fail(f"{prefix}.{field} must be an array of 3 numbers.")
        scale = slot.get("scale", [1.0, 1.0, 1.0])
        if (
            not isinstance(scale, list)
            or len(scale) != 3
            or not all(isinstance(value, (int, float)) and value > 0 for value in scale)
        ):
            _fail(f"{prefix}.scale must be an array of 3 positive numbers.")

    # -----------------------------------------------------------------------
    # Waypoints
    # -----------------------------------------------------------------------
    waypoints = recipe.get("waypoints")
    if not isinstance(waypoints, dict):
        _fail("recipe.waypoints must be an object.")
    for wp_name, pos in waypoints.items():
        if not isinstance(pos, list) or len(pos) != 3 or not all(isinstance(v, (int, float)) for v in pos):
            _fail(f"Waypoint '{wp_name}' must be an array of 3 numbers.")

    # -----------------------------------------------------------------------
    # Immutable anchors validation
    # -----------------------------------------------------------------------
    anchors = recipe.get("immutable_anchors")
    if not isinstance(anchors, list):
        _fail("recipe.immutable_anchors must be an array.")

    anchor_set: dict[str, set[str]] = {}  # target_type:target_id -> {locked_fields}
    anchor_targets: set[str] = set()

    for i, anchor in enumerate(anchors):
        prefix = f"recipe.immutable_anchors[{i}]"
        if not isinstance(anchor, dict):
            _fail(f"{prefix} is not an object.")

        anchor_id = anchor.get("anchor_id", "")
        _validate_snake_id(anchor_id, f"{prefix}.anchor_id")

        anchor_type = anchor.get("anchor_type", "")
        if anchor_type not in VALID_ANCHOR_TYPES:
            _fail(
                f"{prefix}.anchor_type='{anchor_type}' not in {sorted(VALID_ANCHOR_TYPES)}."
            )

        target = anchor.get("target", "")
        locked_fields = anchor.get("locked_fields", [])
        if not isinstance(locked_fields, list) or len(locked_fields) == 0:
            _fail(f"{prefix}.locked_fields must be a non-empty array of field names.")

        # Track anchor targets to prevent variable field overlap
        key = f"{anchor_type}:{target}"
        if key not in anchor_set:
            anchor_set[key] = set()
        for f in locked_fields:
            anchor_set[key].add(f)
        anchor_targets.add(target)

    # -----------------------------------------------------------------------
    # Variable fields validation — must not overlap immutable anchors
    # -----------------------------------------------------------------------
    var_fields = recipe.get("variable_fields")
    if not isinstance(var_fields, list):
        _fail("recipe.variable_fields must be an array.")

    for i, vf in enumerate(var_fields):
        prefix = f"recipe.variable_fields[{i}]"
        if not isinstance(vf, dict):
            _fail(f"{prefix} is not an object.")

        field_path = vf.get("field_path", "")
        if not isinstance(field_path, str) or not field_path:
            _fail(f"{prefix}.field_path must be a non-empty string.")

        # Parse field_path
        parsed = parse_variable_path(field_path, prefix, slot_by_semantic, waypoints)

        if parsed["type"] == "object_slot":
            sid = parsed["target"]
            if sid not in slot_by_semantic:
                _fail(f"{prefix}: target semantic_id '{sid}' not found in object_slots.")

            anchor_key = f"object_slot:{sid}"
            if anchor_key in anchor_set and parsed.get("field"):
                locked = anchor_set[anchor_key]
                if parsed["field"] in locked:
                    _fail(
                        f"{prefix}: field '{parsed['field']}' is locked by an immutable anchor "
                        f"for semantic_id '{sid}'; cannot be marked as variable."
                    )

        elif parsed["type"] == "waypoint":
            wp_name = parsed["target"]
            if wp_name not in waypoints:
                _fail(f"{prefix}: waypoint '{wp_name}' not found in recipe waypoints.")

            anchor_key = f"waypoint:{wp_name}"
            if anchor_key in anchor_set:
                locked = anchor_set[anchor_key]
                if "position" in locked:
                    _fail(
                        f"{prefix}: waypoint '{wp_name}' position is locked by an immutable "
                        f"anchor; cannot be marked as variable."
                    )

        elif parsed["type"] == "opening":
            openings = recipe.get("room", {}).get("openings", [])
            opening_ids = {o.get("opening_id", "") for o in openings}
            if parsed["target"] not in opening_ids:
                _fail(
                    f"{prefix}: opening '{parsed['target']}' not found in recipe room.openings."
                )

            anchor_key = f"opening:{parsed['target']}"
            if anchor_key in anchor_set and parsed.get("field"):
                locked = anchor_set[anchor_key]
                if parsed["field"] in locked:
                    _fail(
                        f"{prefix}: field '{parsed['field']}' is locked by an immutable anchor "
                        f"for opening '{parsed['target']}'."
                    )

        elif parsed["type"] == "room_dimension":
            anchor_key = "room_dimension:room"
            if anchor_key in anchor_set and parsed.get("field"):
                locked = anchor_set[anchor_key]
                if parsed["field"] in locked:
                    _fail(
                        f"{prefix}: field '{parsed['field']}' is locked by an immutable anchor "
                        f"for room dimensions."
                    )

        elif parsed["type"] == "seed":
            pass  # seed is always allowed as variable

        else:
            # Unrecognized path formats are rejected (not warned)
            _fail(
                f"{prefix}: unrecognized variable field path format: '{field_path}'. "
                f"Forward compatibility requires a new schema version."
            )
