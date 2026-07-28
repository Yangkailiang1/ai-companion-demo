"""Spatial constraint validation for generated room layouts."""

# Verifies: S4.2

import copy
import unittest

from tests.scene_generation.fixtures import ShadowContractFixture
from tools.scene_generation.layout_constraints import validate_sampled_layout
from tools.scene_generation.layout_sampler import sample_layout
from tools.scene_generation.scene_contract_error import SceneContractError


class TestLayoutConstraints(ShadowContractFixture, unittest.TestCase):
    def test_seed_batch_passes_spatial_contract(self):
        for seed in range(42, 74):
            recipe = copy.deepcopy(self.recipe)
            recipe["seed"] = seed
            slots = sample_layout(recipe)
            validate_sampled_layout(recipe, self.registry, slots)

    def test_overlapping_floor_furniture_is_rejected(self):
        slots = sample_layout(self.recipe)
        by_id = {slot["semantic_id"]: slot for slot in slots}
        by_id["sofa"]["position"] = by_id["coffee_table"]["position"].copy()
        with self.assertRaises(SceneContractError):
            validate_sampled_layout(self.recipe, self.registry, slots)

    def test_out_of_bounds_interaction_point_is_rejected(self):
        slots = sample_layout(self.recipe)
        slots[0]["interaction_point"] = [99.0, 0.0, 99.0]
        with self.assertRaises(SceneContractError):
            validate_sampled_layout(self.recipe, self.registry, slots)


if __name__ == "__main__":
    unittest.main()
