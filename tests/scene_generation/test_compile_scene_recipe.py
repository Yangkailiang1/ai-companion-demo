"""Positive and deterministic S4.1 scene recipe compilation tests."""

# Verifies: S4.1

import copy
import json
import os
import re
import sys
import tempfile
import unittest

from tests.scene_generation.fixtures import PROJECT_ROOT, ShadowContractFixture

sys.path.insert(0, PROJECT_ROOT)

from tools.scene_generation.compile_scene_recipe import compile_recipe


class TestCompileSceneRecipe(ShadowContractFixture, unittest.TestCase):
    """Verify valid compilation, deterministic bytes and seed identity."""

    def test_valid_compilation(self):
        generation_hash = compile_recipe(self.recipe, self.registry)
        self.assertRegex(generation_hash, r"^[a-f0-9]{64}$")

    def test_changed_seed_changes_hash(self):
        baseline = compile_recipe(self.recipe, self.registry)
        changed = copy.deepcopy(self.recipe)
        changed["seed"] += 1
        self.assertNotEqual(baseline, compile_recipe(changed, self.registry))

    def test_deterministic_manifest_bytes(self):
        paths = []
        try:
            for _index in range(2):
                handle = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
                handle.close()
                paths.append(handle.name)
                compile_recipe(
                    copy.deepcopy(self.recipe),
                    copy.deepcopy(self.registry),
                    output_path=handle.name,
                )
            with open(paths[0], "rb") as first, open(paths[1], "rb") as second:
                self.assertEqual(first.read(), second.read())
        finally:
            for path in paths:
                if os.path.isfile(path):
                    os.unlink(path)

    def test_manifest_contract_fields(self):
        handle = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
        handle.close()
        try:
            compile_recipe(self.recipe, self.registry, output_path=handle.name)
            with open(handle.name, encoding="utf-8") as manifest_file:
                manifest = json.load(manifest_file)
            self.assertRegex(manifest["manifest_id"], r"^[a-z][a-z0-9_-]*$")
            self.assertEqual(manifest["recipe_id"], self.recipe["recipe_id"])
            self.assertEqual(manifest["seed"], self.recipe["seed"])
            self.assertEqual(
                len(manifest["placements"]), len(self.recipe["object_slots"])
            )
            self.assertEqual(manifest["audit"]["compiler_version"], "1.1.0")
            self.assertNotIn("generated_at", manifest["audit"])
            # [S4.1] New assertions: manifest room carries bounds, floor, walls, openings.
            self.assertIn("bounds", manifest["room"])
            self.assertIn("floor", manifest["room"])
            self.assertIn("walls", manifest["room"])
            self.assertIn("openings", manifest["room"])
            self.assertEqual(manifest["room"]["bounds"], self.recipe["room"]["bounds"])
            self.assertEqual(manifest["room"]["floor"], self.recipe["room"]["floor"])
            self.assertEqual(manifest["room"]["walls"], self.recipe["room"]["walls"])
            self.assertEqual(manifest["room"]["openings"], self.recipe["room"]["openings"])
        finally:
            os.unlink(handle.name)


if __name__ == "__main__":
    unittest.main()
