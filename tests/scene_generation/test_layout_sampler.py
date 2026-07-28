"""Deterministic multi-seed layout sampling tests."""

# Verifies: S4.2

import copy
import unittest

from tests.scene_generation.fixtures import ShadowContractFixture
from tools.scene_generation.layout_sampler import sample_layout


class TestLayoutSampler(ShadowContractFixture, unittest.TestCase):
    def test_baseline_seed_preserves_authored_layout(self):
        self.assertEqual(sample_layout(self.recipe), self.recipe["object_slots"])

    def test_same_seed_is_deterministic(self):
        changed = copy.deepcopy(self.recipe)
        changed["seed"] = 43
        self.assertEqual(sample_layout(changed), sample_layout(changed))

    def test_different_seed_changes_only_declared_positions(self):
        changed = copy.deepcopy(self.recipe)
        changed["seed"] = 43
        sampled = sample_layout(changed)
        baseline = {slot["semantic_id"]: slot for slot in self.recipe["object_slots"]}
        result = {slot["semantic_id"]: slot for slot in sampled}
        self.assertNotEqual(result["coffee_table"]["position"], baseline["coffee_table"]["position"])
        for semantic_id in ("tv", "plant", "window"):
            self.assertEqual(result[semantic_id], baseline[semantic_id])

    def test_tabletop_objects_follow_table_delta(self):
        changed = copy.deepcopy(self.recipe)
        changed["seed"] = 43
        result = {slot["semantic_id"]: slot for slot in sample_layout(changed)}
        baseline = {slot["semantic_id"]: slot for slot in self.recipe["object_slots"]}
        table_delta = [
            result["coffee_table"]["position"][index]
            - baseline["coffee_table"]["position"][index]
            for index in range(3)
        ]
        for semantic_id in ("book", "milk_tea"):
            item_delta = [
                result[semantic_id]["position"][index]
                - baseline[semantic_id]["position"][index]
                for index in range(3)
            ]
            for item_axis, table_axis in zip(item_delta, table_delta):
                self.assertAlmostEqual(item_axis, table_axis, places=6)


if __name__ == "__main__":
    unittest.main()
