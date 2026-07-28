"""Negative S4.1 scene Recipe and Asset Registry contract tests."""

# Verifies: S4.1

import copy
import sys
import unittest

from tests.scene_generation.fixtures import PROJECT_ROOT, ShadowContractFixture

sys.path.insert(0, PROJECT_ROOT)

from tools.scene_generation.compile_scene_recipe import compile_recipe
from tools.scene_generation.scene_contract_error import SceneContractError


class TestSceneContractRejections(ShadowContractFixture, unittest.TestCase):
    """Verify invalid identities, references and mutation paths fail closed."""

    def assert_contract_error(self, recipe=None, registry=None):
        with self.assertRaises(SceneContractError):
            compile_recipe(recipe or self.recipe, registry or self.registry)

    def test_missing_asset(self):
        self.recipe["object_slots"][0]["asset_id"] = "nonexistent_asset"
        self.assert_contract_error()

    def test_duplicate_semantic_id(self):
        self.recipe["object_slots"].append(
            copy.deepcopy(self.recipe["object_slots"][0])
        )
        self.assert_contract_error()

    def test_illegal_immutable_variable_path(self):
        self.recipe["variable_fields"].append(
            {"field_path": "object_slots[plant].semantic_id"}
        )
        self.assert_contract_error()

    def test_unknown_recipe_field(self):
        self.recipe["garbage_field"] = True
        self.assert_contract_error()

    def test_unknown_registry_field(self):
        self.registry["garbage_field"] = True
        self.assert_contract_error()

    def test_unknown_nested_asset_field(self):
        self.registry["assets"][0]["garbage_nested"] = True
        self.assert_contract_error()

    def test_unknown_nested_slot_field(self):
        self.recipe["object_slots"][0]["garbage_nested"] = True
        self.assert_contract_error()

    def test_missing_required_asset_field(self):
        del self.registry["assets"][0]["roles"]
        self.assert_contract_error()

    def test_missing_required_slot_field(self):
        del self.recipe["object_slots"][0]["display_name"]
        self.assert_contract_error()

    def test_malformed_semantic_id(self):
        self.recipe["object_slots"][0]["semantic_id"] = "BAD-ID"
        self.assert_contract_error()

    def test_malformed_asset_id(self):
        self.recipe["object_slots"][0]["asset_id"] = "INVALID@ID"
        self.assert_contract_error()

    def test_registry_id_mismatch(self):
        self.recipe["registry_id"] = "wrong_registry"
        self.assert_contract_error()

    def test_registry_version_mismatch(self):
        self.recipe["registry_version"] = "99.99.99"
        self.assert_contract_error()

    def test_unrecognized_variable_path(self):
        self.recipe["variable_fields"].append(
            {"field_path": "garbage_path.whatever"}
        )
        self.assert_contract_error()

    def test_missing_waypoint_variable_target(self):
        self.recipe["variable_fields"].append(
            {"field_path": "waypoints[missing_waypoint]"}
        )
        self.assert_contract_error()

    def test_missing_required_recipe_field(self):
        del self.recipe["room"]
        self.assert_contract_error()

    def test_empty_object_slots(self):
        self.recipe["object_slots"] = []
        self.assert_contract_error()

    def test_invalid_position_array(self):
        self.recipe["object_slots"][0]["position"] = [1.0, 2.0]
        self.assert_contract_error()

    def test_non_integer_seed(self):
        self.recipe["seed"] = "forty-two"
        self.assert_contract_error()

    def test_unknown_layout_generator(self):
        self.recipe["variable_fields"][0]["constraints"] = {
            "generator": "teleport_anywhere"
        }
        self.assert_contract_error()

    def test_follow_target_must_exist(self):
        self.recipe["variable_fields"][2]["constraints"] = {
            "generator": "follow",
            "target": "missing_table",
        }
        self.assert_contract_error()

    def test_multiple_openings_on_same_wall_are_rejected_in_v1(self):
        duplicate = copy.deepcopy(self.recipe["room"]["openings"][0])
        duplicate["opening_id"] = "second_window"
        self.recipe["room"]["openings"].append(duplicate)
        self.assert_contract_error()


if __name__ == "__main__":
    unittest.main()
