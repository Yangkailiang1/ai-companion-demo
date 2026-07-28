"""Asset Registry structural validation.

Roadmap: S4.1
Responsibility: Validate registry identity and asset entry fields, returning the
stable asset lookup used by recipe cross-reference validation.
"""

# Verifies: S4.1

import re
from typing import Any

from tools.scene_generation.scene_contract_error import SceneContractError

_ID_RE = re.compile(r"^[a-z][a-z0-9_]*(?:_[a-z0-9_]+)*$")
_VERSION_RE = re.compile(r"^\d+\.\d+\.\d+$")
_TOP_LEVEL_FIELDS = frozenset(
    {"schema_version", "registry_id", "registry_version", "description", "assets"}
)
_ASSET_FIELDS = frozenset(
    {
        "asset_id",
        "display_name",
        "resource_path",
        "provenance",
        "geometry",
        "roles",
        "style_tags",
        "interaction_profile",
        "capabilities",
        "placement_profile",
        "status",
    }
)
_ASSET_REQUIRED_FIELDS = frozenset(
    {
        "asset_id",
        "display_name",
        "provenance",
        "roles",
        "style_tags",
        "interaction_profile",
        "capabilities",
        "placement_profile",
        "status",
    }
)


def _require_pattern(value: Any, pattern: re.Pattern, label: str) -> None:
    if not isinstance(value, str) or pattern.fullmatch(value) is None:
        raise SceneContractError(f"{label} '{value}' has an invalid format.")


def _reject_unknown(data: dict, allowed: frozenset, label: str) -> None:
    unknown = set(data) - allowed
    if unknown:
        field = sorted(unknown)[0]
        raise SceneContractError(f"Unknown field '{field}' in {label}.")


def validate_registry(registry: dict) -> dict[str, dict]:
    """[S4.1] Validate registry identity and return asset_id-to-entry lookup."""
    if not isinstance(registry, dict):
        raise SceneContractError("registry must be an object.")
    _reject_unknown(registry, _TOP_LEVEL_FIELDS, "registry")
    for field in ("schema_version", "registry_id", "registry_version", "assets"):
        if field not in registry:
            raise SceneContractError(f"Missing required field '{field}' in registry.")
    if not isinstance(registry["schema_version"], int) or registry["schema_version"] < 1:
        raise SceneContractError("registry.schema_version must be a positive integer.")
    _require_pattern(registry["registry_id"], _ID_RE, "registry.registry_id")
    _require_pattern(
        registry["registry_version"], _VERSION_RE, "registry.registry_version"
    )
    return _validate_assets(registry["assets"])


def _validate_assets(assets: Any) -> dict[str, dict]:
    """[S4.1] Reject duplicate IDs and fields outside the asset contract."""
    if not isinstance(assets, list) or not assets:
        raise SceneContractError("registry.assets must be a non-empty array.")
    asset_map: dict[str, dict] = {}
    for index, entry in enumerate(assets):
        label = f"registry.assets[{index}]"
        if not isinstance(entry, dict):
            raise SceneContractError(f"{label} is not an object.")
        _reject_unknown(entry, _ASSET_FIELDS, label)
        missing = _ASSET_REQUIRED_FIELDS - set(entry)
        if missing:
            field = sorted(missing)[0]
            raise SceneContractError(f"Missing required field '{field}' in {label}.")
        asset_id = entry.get("asset_id", "")
        _require_pattern(asset_id, _ID_RE, f"{label}.asset_id")
        if asset_id in asset_map:
            raise SceneContractError(
                f"Duplicate asset_id '{asset_id}' in registry.assets."
            )
        asset_map[asset_id] = entry
    return asset_map
