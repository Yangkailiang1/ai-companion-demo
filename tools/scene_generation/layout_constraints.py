"""Fail-closed spatial checks for sampled scene layouts.

Roadmap: S4.2
Responsibility: Validate floor bounds, furniture overlap, surface parents and
interaction-point safety using Recipe + Registry data.
Tests: tests/scene_generation/test_layout_constraints.py
"""

# Verifies: S4.2

import math

from tools.scene_generation.scene_contract_error import SceneContractError


def validate_sampled_layout(recipe: dict, registry: dict, slots: list[dict]) -> None:
    """[S4.2] Reject sampled layouts that violate core spatial constraints."""
    assets = {entry["asset_id"]: entry for entry in registry["assets"]}
    slot_map = {slot["semantic_id"]: slot for slot in slots}
    _validate_interaction_points(recipe, slots)
    floor_rects: list[tuple[str, tuple[float, float, float, float]]] = []

    width = float(recipe["room"]["dimensions_m"]["width"])
    depth = float(recipe["room"]["dimensions_m"]["depth"])
    for slot in slots:
        asset = assets[slot["asset_id"]]
        placement_role = asset["roles"].get("placement", "")
        if placement_role == "surface":
            _validate_surface_parent(recipe, slot, slot_map)
            continue
        if placement_role != "floor":
            continue
        rectangle = _floor_rectangle(slot, asset)
        tolerance = 0.15 if "near_wall" in asset["placement_profile"]["preferred_zone"] else 0.0
        if (
            rectangle[0] < -width * 0.5 - tolerance
            or rectangle[2] > width * 0.5 + tolerance
            or rectangle[1] < -depth * 0.5 - tolerance
            or rectangle[3] > depth * 0.5 + tolerance
        ):
            raise SceneContractError(
                f"floor object '{slot['semantic_id']}' exceeds room bounds."
            )
        floor_rects.append((slot["semantic_id"], rectangle))

    for index, (left_id, left) in enumerate(floor_rects):
        for right_id, right in floor_rects[index + 1 :]:
            if _overlaps(left, right):
                raise SceneContractError(
                    f"floor objects '{left_id}' and '{right_id}' overlap."
                )


def _validate_interaction_points(recipe: dict, slots: list[dict]) -> None:
    bounds = recipe["room"].get("bounds", {})
    minimum = bounds.get("min")
    maximum = bounds.get("max")
    if not minimum or not maximum:
        return
    for slot in slots:
        point = slot["interaction_point"]
        if not (
            float(minimum[0]) <= float(point[0]) <= float(maximum[0])
            and float(minimum[2]) <= float(point[2]) <= float(maximum[2])
        ):
            raise SceneContractError(
                f"interaction point for '{slot['semantic_id']}' is outside safe bounds."
            )


def _validate_surface_parent(recipe: dict, slot: dict, slot_map: dict) -> None:
    variable = next(
        (
            entry
            for entry in recipe.get("variable_fields", [])
            if entry["field_path"] == f"object_slots[{slot['semantic_id']}].position"
        ),
        None,
    )
    constraints = variable.get("constraints", {}) if variable else {}
    if constraints.get("generator") != "follow":
        raise SceneContractError(
            f"surface object '{slot['semantic_id']}' must declare a follow generator."
        )
    if constraints.get("target") not in slot_map:
        raise SceneContractError(
            f"surface object '{slot['semantic_id']}' has no valid parent target."
        )


def _floor_rectangle(slot: dict, asset: dict) -> tuple[float, float, float, float]:
    size = asset["geometry"]["aabb_m"]
    rotation_y = math.radians(float(slot.get("rotation_deg", [0, 0, 0])[1]))
    extent_x = abs(math.cos(rotation_y)) * float(size[0]) + abs(
        math.sin(rotation_y)
    ) * float(size[2])
    extent_z = abs(math.sin(rotation_y)) * float(size[0]) + abs(
        math.cos(rotation_y)
    ) * float(size[2])
    x = float(slot["position"][0])
    z = float(slot["position"][2])
    return (
        x - extent_x * 0.5,
        z - extent_z * 0.5,
        x + extent_x * 0.5,
        z + extent_z * 0.5,
    )


def _overlaps(
    left: tuple[float, float, float, float],
    right: tuple[float, float, float, float],
) -> bool:
    epsilon = 0.02
    return (
        left[0] < right[2] - epsilon
        and left[2] > right[0] + epsilon
        and left[1] < right[3] - epsilon
        and left[3] > right[1] + epsilon
    )
