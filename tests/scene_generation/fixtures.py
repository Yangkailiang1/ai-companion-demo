"""Shared S4.1 scene-contract test fixtures."""

import copy
import json
import os

PROJECT_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)


class ShadowContractFixture:
    """Load an isolated copy of the living-room shadow contract per test."""

    @classmethod
    def setUpClass(cls):
        base = os.path.join(PROJECT_ROOT, "data", "scene_generation")
        with open(
            os.path.join(base, "recipes", "living_room_shadow.recipe.json"),
            encoding="utf-8",
        ) as handle:
            cls.shadow_recipe = json.load(handle)
        with open(
            os.path.join(base, "registries", "living_room_shadow_registry.json"),
            encoding="utf-8",
        ) as handle:
            cls.shadow_registry = json.load(handle)

    def setUp(self):
        self.recipe = copy.deepcopy(self.shadow_recipe)
        self.registry = copy.deepcopy(self.shadow_registry)
