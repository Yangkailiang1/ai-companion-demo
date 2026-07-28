"""Scene recipe compiler that builds deterministic generation manifests.

Roadmap: S4.1
Responsibility: Compile a validated recipe + registry into a deterministic
generated_scene_manifest with SHA-256 hash. Never modifies Godot world state.
Tests: tests/scene_generation/test_compile_scene_recipe.py
"""

# Verifies: S4.1

import hashlib
import json
import re
from typing import Any, Optional

from tools.scene_generation.contract_validator import validate_registry, validate_recipe
from tools.scene_generation.layout_constraints import validate_sampled_layout
from tools.scene_generation.layout_sampler import sample_layout
from tools.scene_generation.scene_contract_error import SceneContractError

# manifest_id must match the generated_scene_manifest schema pattern:
#   ^[a-z][a-z0-9_-]*$
_MANIFEST_ID_RE = re.compile(r"^[a-z][a-z0-9_-]*$")


def compile_recipe(
    recipe: dict,
    registry: dict,
    output_path: Optional[str] = None,
) -> str:
    """[S4.1] Validate and compile a recipe into a manifest.

    Returns the generation_hash (SHA-256).
    Writes the manifest JSON to output_path only when explicitly provided.
    Raises SceneContractError on any validation or contract failure.
    """
    # Validate registry first
    asset_map = validate_registry(registry)

    # Enforce exact recipe.registry_id == registry.registry_id
    if recipe.get("registry_id") != registry["registry_id"]:
        raise SceneContractError(
            f"recipe.registry_id '{recipe.get('registry_id')}' does not match "
            f"registry.registry_id '{registry['registry_id']}'."
        )

    # Enforce exact recipe.registry_version == registry.registry_version
    if recipe.get("registry_version") != registry["registry_version"]:
        raise SceneContractError(
            f"recipe.registry_version '{recipe.get('registry_version')}' does not match "
            f"registry.registry_version '{registry['registry_version']}'."
        )

    # Validate recipe (includes cross-reference checks)
    validate_recipe(recipe, asset_map)

    # Build generation hash: canonical JSON of (recipe + registry_version + seed)
    canonical = _canonical_json(
        {
            "recipe": recipe,
            "registry_version": registry["registry_version"],
            "seed": recipe["seed"],
        }
    )
    gen_hash = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    sampled_slots = sample_layout(recipe)
    validate_sampled_layout(recipe, registry, sampled_slots)

    if output_path is None:
        # Validation-only mode: print summary
        print("Recipe validation: PASSED")
        print(f"  recipe_id:      {recipe['recipe_id']}")
        print(f"  registry_id:    {recipe['registry_id']}")
        print(f"  registry_version: {recipe['registry_version']}")
        print(f"  seed:           {recipe['seed']}")
        print(f"  object_slots:   {len(recipe['object_slots'])}")
        print(f"  waypoints:      {len(recipe['waypoints'])}")
        print(f"  immutable_anchors: {len(recipe['immutable_anchors'])}")
        print(f"  variable_fields:   {len(recipe['variable_fields'])}")
        print(f"  generation_hash:   {gen_hash}")
        return gen_hash

    # Build manifest
    manifest = _build_manifest(recipe, gen_hash, sampled_slots)
    manifest["audit"] = {
        "compiler_version": "1.1.0",
        "warnings": [],
    }

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"Manifest written to: {output_path}")
    print(f"  generation_hash: {gen_hash}")
    return gen_hash


def _canonical_json(obj: Any) -> str:
    """[S4.1] Produce a canonical (sorted keys) JSON representation for hashing."""
    return json.dumps(obj, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def _build_manifest(recipe: dict, gen_hash: str, sampled_slots: list[dict]) -> dict:
    """[S4.1] Build the generated_scene_manifest from a validated recipe."""
    short_hash = gen_hash[:12]
    manifest_id = f"{recipe['recipe_id']}-{recipe['seed']}-{short_hash}"

    # Validate manifest_id against schema pattern
    if not _MANIFEST_ID_RE.match(manifest_id):
        raise SceneContractError(
            f"Generated manifest_id '{manifest_id}' does not match "
            f"required pattern '^[a-z][a-z0-9_-]*$'."
        )

    placements = []
    for slot in sampled_slots:
        placements.append(
            {
                "semantic_id": slot["semantic_id"],
                "asset_id": slot["asset_id"],
                "display_name": slot["display_name"],
                "position": slot["position"],
                "rotation_deg": slot.get("rotation_deg", [0, 0, 0]),
                "interaction_point": slot["interaction_point"],
                "description": slot.get("description", ""),
                "needs_proximity": slot.get("needs_proximity", True),
                "affordances": slot.get("affordances", []),
                "effects": slot.get("effects", {}),
                "initial_state": slot.get("initial_state", ""),
                "properties": slot.get("properties", {}),
                "consumable": slot.get("consumable", False),
            }
        )

    recipe_room = recipe["room"]
    return {
        "schema_version": 1,
        "manifest_id": manifest_id,
        "recipe_id": recipe["recipe_id"],
        "recipe_version": recipe["recipe_version"],
        "registry_id": recipe["registry_id"],
        "registry_version": recipe["registry_version"],
        "seed": recipe["seed"],
        "generation_hash": gen_hash,
        "room": {
            "name": recipe_room["name"],
            "dimensions_m": recipe_room["dimensions_m"],
            "bounds": recipe_room.get("bounds", {}),
            "floor": recipe_room.get("floor", {}),
            "walls": recipe_room.get("walls", []),
            "openings": recipe_room.get("openings", []),
        },
        "placements": placements,
    }
