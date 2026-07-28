"""Scene contract validation error.

Roadmap: S4.1
Responsibility: Provide a dedicated exception for contract validation failures.
Only the CLI layer may convert this to process exit 1.
Tests: tests/scene_generation/test_compile_scene_recipe.py
"""

# Verifies: S4.1


class SceneContractError(Exception):
    """Raised when a scene contract (recipe or registry) fails validation.

    Unlike sys.exit(), this can be caught and tested in library code.
    """

    pass
