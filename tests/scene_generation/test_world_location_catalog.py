"""Static contract checks for the S2.2 generated multi-room home."""

from __future__ import annotations

import json
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
CATALOG_PATH = PROJECT_ROOT / "data/world_locations.json"


class WorldLocationCatalogTests(unittest.TestCase):
    """Keep every graph edge, recipe output and packaged resource resolvable."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
        cls.locations = cls.catalog["locations"]

    def test_catalog_has_first_home_rooms(self) -> None:
        self.assertEqual(self.catalog["schema_version"], 1)
        self.assertEqual(self.catalog["default_location_id"], "living_room")
        self.assertEqual(set(self.locations), {"living_room", "kitchen", "bedroom"})

    def test_location_resources_exist(self) -> None:
        for location_id, location in self.locations.items():
            for field in ("scene_path", "manifest_path", "registry_path"):
                path = self._project_path(location[field])
                self.assertTrue(path.is_file(), f"{location_id}.{field}: {path}")
            self.assertIn("default", location["entries"])
            self.assertIn("Agent", location["cast_spawns"])
            self.assertIn("JueAgent", location["cast_spawns"])

    def test_every_exit_targets_a_declared_entry(self) -> None:
        for source_id, source in self.locations.items():
            for exit_id, edge in source["exits"].items():
                target_id = edge["target_location_id"]
                self.assertIn(target_id, self.locations, f"{source_id}.{exit_id}")
                self.assertIn(
                    edge["target_entry_id"],
                    self.locations[target_id]["entries"],
                    f"{source_id}.{exit_id}",
                )

    def test_manifest_registry_versions_match(self) -> None:
        for location_id, location in self.locations.items():
            manifest = json.loads(
                self._project_path(location["manifest_path"]).read_text(encoding="utf-8")
            )
            registry = json.loads(
                self._project_path(location["registry_path"]).read_text(encoding="utf-8")
            )
            self.assertEqual(
                manifest["registry_version"],
                registry["registry_version"],
                location_id,
            )
            self.assertGreater(len(manifest["placements"]), 0, location_id)

    @staticmethod
    def _project_path(resource_path: str) -> Path:
        if not resource_path.startswith("res://"):
            raise AssertionError(f"not a project resource: {resource_path}")
        return PROJECT_ROOT / resource_path.removeprefix("res://")


if __name__ == "__main__":
    unittest.main()
