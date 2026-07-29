"""Golden-path tests for safe scene asset normalization.

Roadmap: O2.1
Responsibility: Verify source-ID preservation, deterministic publication, and
failure rollback; never touch live project assets or network state.
Tests: Run this module with Python unittest.
"""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from tools.assets import normalize_kitchen_registry as normalizer


class NormalizeKitchenRegistryTest(unittest.TestCase):
    """Verify the O2.1 golden asset publication contract."""

    def setUp(self) -> None:
        """Create one mixed-case quarantined fixture.

        Roadmap: O2.1
        Side effects: Writes only inside a temporary directory.
        """
        self.temp_dir = tempfile.TemporaryDirectory()
        self.project_root = Path(self.temp_dir.name) / "project"
        self.quarantine_root = Path(self.temp_dir.name) / "quarantine"
        self.output_root = (
            self.project_root / "assets" / "props" / "polyhaven"
        )
        self.source_id = "WoodenTable_01"
        source_dir = self.quarantine_root / self.source_id
        source_dir.mkdir(parents=True)
        (source_dir / "WoodenTable_01.bin").write_bytes(b"fixture")
        gltf = {
            "buffers": [{"uri": "WoodenTable_01.bin"}],
            "accessors": [{"count": 6}, {"count": 4}],
            "meshes": [{
                "primitives": [{
                    "indices": 0,
                    "attributes": {"POSITION": 1},
                }],
            }],
        }
        (source_dir / "WoodenTable_01_1k.gltf").write_text(
            json.dumps(gltf), encoding="utf-8"
        )
        self.provenance = {
            "asset_id": self.source_id,
            "provider": "polyhaven",
            "license": "CC0-1.0",
            "redistribution": "allowed",
            "sha256": "fixture-sha",
            "status": "downloaded",
        }
        (source_dir / f"{self.source_id}.provenance.json").write_text(
            json.dumps(self.provenance), encoding="utf-8"
        )

    def tearDown(self) -> None:
        """Release the isolated fixture.

        Roadmap: O2.1
        Side effects: Deletes only the unittest temporary directory.
        """
        self.temp_dir.cleanup()

    def _normalize(self) -> dict:
        """Run the normalizer against isolated roots.

        Roadmap: O2.1
        Side effects: Publishes only below the fixture project root.
        """
        return normalizer.normalize_asset(
            self.source_id,
            self.provenance,
            quarantine_root=self.quarantine_root,
            output_root=self.output_root,
            project_root=self.project_root,
        )

    def test_mixed_case_source_is_idempotent_and_portable(self) -> None:
        """Require stable hashes and res paths across two publications.

        Roadmap: O2.1
        """
        first = self._normalize()
        second = self._normalize()
        self.assertEqual(first["resource_hash"], second["resource_hash"])
        self.assertEqual("woodentable_01", first["asset_id"])
        self.assertTrue(first["resource_path"].startswith("res://"))
        provenance_path = (
            self.output_root / "woodentable_01"
            / f"{self.source_id}.provenance.json"
        )
        published = json.loads(provenance_path.read_text(encoding="utf-8"))
        self.assertEqual("inventoried", published["status"])
        self.assertTrue(published["main_file"].startswith("res://"))
        self.assertNotIn(self.temp_dir.name, published["main_file"])

    def test_missing_source_keeps_existing_target(self) -> None:
        """Require pre-validation failure to preserve existing output.

        Roadmap: O2.1
        """
        target_dir = self.output_root / "missingasset"
        target_dir.mkdir(parents=True)
        sentinel = target_dir / "sentinel.txt"
        sentinel.write_text("keep", encoding="utf-8")
        with self.assertRaises(FileNotFoundError):
            normalizer.normalize_asset(
                "MissingAsset",
                {"asset_id": "MissingAsset", "redistribution": "allowed"},
                quarantine_root=self.quarantine_root,
                output_root=self.output_root,
                project_root=self.project_root,
            )
        self.assertEqual("keep", sentinel.read_text(encoding="utf-8"))

    def test_local_only_source_is_rejected_before_publish(self) -> None:
        """Require license automation to fail closed.

        Roadmap: O2.1
        """
        restricted = dict(self.provenance)
        restricted["redistribution"] = "local_only"
        with self.assertRaises(ValueError):
            normalizer.normalize_asset(
                self.source_id,
                restricted,
                quarantine_root=self.quarantine_root,
                output_root=self.output_root,
                project_root=self.project_root,
            )


if __name__ == "__main__":
    unittest.main()
