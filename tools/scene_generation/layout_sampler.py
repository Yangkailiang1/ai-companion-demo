"""Deterministic layout sampling for declared scene-recipe variable fields.

Roadmap: S4.2
Responsibility: Resolve machine-readable position constraints into placement
positions without mutating the source recipe.
Tests: tests/scene_generation/test_layout_sampler.py
"""

# Verifies: S4.2

import copy
import hashlib
import random

from tools.scene_generation.scene_contract_error import SceneContractError
from tools.scene_generation.variable_path_parser import parse_variable_path


def sample_layout(recipe: dict) -> list[dict]:
    """[S4.2] Return object slots sampled deterministically for recipe.seed."""
    slots = copy.deepcopy(recipe["object_slots"])
    slot_map = {slot["semantic_id"]: slot for slot in slots}
    source_map = {slot["semantic_id"]: slot for slot in recipe["object_slots"]}
    variables = recipe.get("variable_fields", [])
    supported_generators = {"uniform_offset", "follow"}
    for variable in variables:
        constraints = variable.get("constraints", {})
        generator = constraints.get("generator")
        if generator is not None and generator not in supported_generators:
            raise SceneContractError(f"Unsupported layout generator '{generator}'.")

    # Independent offsets run first so follower objects can inherit final poses.
    for variable in variables:
        constraints = variable.get("constraints", {})
        if constraints.get("generator") != "uniform_offset":
            continue
        parsed = parse_variable_path(
            variable["field_path"], "variable_field", slot_map, recipe["waypoints"]
        )
        if parsed.get("type") != "object_slot" or parsed.get("field") != "position":
            raise SceneContractError(
                "uniform_offset only supports object_slots[semantic_id].position."
            )
        _apply_uniform_offset(
            slot_map[parsed["target"]], variable["field_path"], recipe["seed"], constraints
        )

    for variable in variables:
        constraints = variable.get("constraints", {})
        if constraints.get("generator") != "follow":
            continue
        parsed = parse_variable_path(
            variable["field_path"], "variable_field", slot_map, recipe["waypoints"]
        )
        if parsed.get("type") != "object_slot" or parsed.get("field") != "position":
            raise SceneContractError(
                "follow only supports object_slots[semantic_id].position."
            )
        target_id = constraints.get("target", "")
        if target_id == parsed["target"]:
            raise SceneContractError("follow target cannot reference itself.")
        if target_id not in slot_map or target_id not in source_map:
            raise SceneContractError(
                f"follow target '{target_id}' does not exist in object_slots."
            )
        _apply_follow(
            slot_map[parsed["target"]],
            slot_map[target_id],
            source_map[target_id],
            constraints,
        )

    return slots


def _apply_uniform_offset(
    slot: dict, field_path: str, seed: int, constraints: dict
) -> None:
    """[S4.2] Apply a stable per-field uniform offset and move its approach point."""
    baseline_seed = constraints.get("baseline_seed")
    if baseline_seed is not None and seed == baseline_seed:
        return
    offset_min = _vector3(constraints.get("offset_min"), "offset_min")
    offset_max = _vector3(constraints.get("offset_max"), "offset_max")
    if any(low > high for low, high in zip(offset_min, offset_max)):
        raise SceneContractError(f"{field_path}: offset_min must be <= offset_max.")

    digest = hashlib.sha256(f"{seed}:{field_path}".encode("utf-8")).digest()
    rng = random.Random(int.from_bytes(digest[:8], "big"))
    delta = [
        round(rng.uniform(offset_min[index], offset_max[index]), 4)
        for index in range(3)
    ]
    slot["position"] = _add(slot["position"], delta)
    if constraints.get("move_interaction_point", True):
        slot["interaction_point"] = _add(slot["interaction_point"], delta)


def _apply_follow(
    slot: dict, target: dict, source_target: dict, constraints: dict
) -> None:
    """[S4.2] Preserve a follower's authored offsets from a sampled target."""
    position_offset = constraints.get("position_offset")
    interaction_offset = constraints.get("interaction_offset")
    if position_offset is None:
        position_offset = _subtract(slot["position"], source_target["position"])
    else:
        position_offset = _vector3(position_offset, "position_offset")
    if interaction_offset is None:
        interaction_offset = _subtract(
            slot["interaction_point"], source_target["position"]
        )
    else:
        interaction_offset = _vector3(interaction_offset, "interaction_offset")
    slot["position"] = _add(target["position"], position_offset)
    slot["interaction_point"] = _add(target["position"], interaction_offset)


def _vector3(value: object, field_name: str) -> list[float]:
    if not isinstance(value, list) or len(value) != 3:
        raise SceneContractError(f"{field_name} must be a three-number array.")
    if any(not isinstance(item, (int, float)) for item in value):
        raise SceneContractError(f"{field_name} must contain only numbers.")
    return [float(item) for item in value]


def _add(left: list, right: list) -> list[float]:
    return [round(float(left[index]) + float(right[index]), 4) for index in range(3)]


def _subtract(left: list, right: list) -> list[float]:
    return [round(float(left[index]) - float(right[index]), 4) for index in range(3)]
