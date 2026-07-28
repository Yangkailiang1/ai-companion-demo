"""CLI entry point for scene recipe compilation.

Roadmap: S4.1
Responsibility: Parse CLI arguments, load files, and delegate validation +
compilation to the library modules. Only this layer converts
SceneContractError to process exit 1.
Tests: tests/scene_generation/test_compile_scene_recipe.py

Public API (preserved import): compile_recipe
"""

# Verifies: S4.1

import argparse
import json
import os
import sys

# Ensure the project root is on sys.path so the tools package is importable
# when this script is invoked directly (not via `python3 -m`).
_PROJECT_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
if _PROJECT_ROOT not in sys.path:
    sys.path.insert(0, _PROJECT_ROOT)

from tools.scene_generation.manifest_builder import compile_recipe
from tools.scene_generation.scene_contract_error import SceneContractError

# Re-export for backwards compatibility
__all__ = ["compile_recipe", "SceneContractError"]


def main() -> None:
    """[S4.1] CLI: load recipe + registry, compile, and print result."""
    parser = argparse.ArgumentParser(
        description="Validate and compile a scene recipe into a deterministic generation manifest."
    )
    parser.add_argument(
        "--recipe",
        required=True,
        help="Path to the scene recipe JSON file.",
    )
    parser.add_argument(
        "--registry",
        required=True,
        help="Path to the asset registry JSON file.",
    )
    parser.add_argument(
        "--output",
        default=None,
        help="Optional path to write the generated_scene_manifest JSON.",
    )
    args = parser.parse_args()

    # Load recipe
    if not os.path.isfile(args.recipe):
        print(f"ERROR: Recipe file not found: {args.recipe}", file=sys.stderr)
        sys.exit(1)
    with open(args.recipe, "r", encoding="utf-8") as f:
        recipe = json.load(f)

    # Load registry
    if not os.path.isfile(args.registry):
        print(f"ERROR: Registry file not found: {args.registry}", file=sys.stderr)
        sys.exit(1)
    with open(args.registry, "r", encoding="utf-8") as f:
        registry = json.load(f)

    try:
        compile_recipe(recipe, registry, args.output)
    except SceneContractError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
