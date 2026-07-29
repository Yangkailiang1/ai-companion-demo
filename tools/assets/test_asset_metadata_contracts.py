"""Asset metadata contract tests.

Roadmap: O2, C2, C3, C6
Responsibility: Validate machine-readable asset contracts for provenance, expression
  adapter candidates, motion package, scene registry, and local character morph
  inventories; never modify models, scenes, Runtime, existing metadata, or Git.
"""
import json
import unittest
from pathlib import Path
from typing import Any

_ROOT = Path(__file__).resolve().parent.parent.parent


def _load(path: Path) -> Any:
    """[O2] Load JSON; side effect: reads disk."""
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def _has_local_characters() -> bool:
    """[O2] True when assets/local_characters/ exists with ≥1 subdirectory."""
    d = _ROOT / "assets" / "local_characters"
    return d.is_dir() and any(e.is_dir() for e in d.iterdir())


class PenguinProvenanceTest(unittest.TestCase):
    """[C6][O2] Verify penguin provenance.json licence and redistribution."""
    _PROV = _ROOT / "assets" / "characters" / "penguin" / "provenance.json"

    def test_license_not_project_authored(self) -> None:
        """[C6] License must not be 'Project-authored'."""
        data = _load(self._PROV)
        self.assertNotEqual("Project-authored", data.get("license", ""),
            "penguin license must not be 'Project-authored'; unknown-source prototype.")

    def test_redistribution_is_local_only(self) -> None:
        """[C6] Redistribution must be 'local_only'."""
        data = _load(self._PROV)
        self.assertEqual("local_only", data.get("redistribution", ""),
            "penguin must be local_only: no public redistribution permitted.")

    def test_no_your_org_placeholder_url(self) -> None:
        """[C6] No 'your-org' placeholder URL anywhere in provenance."""
        raw = json.dumps(_load(self._PROV), ensure_ascii=False)
        self.assertNotIn("your-org", raw,
            "Found 'your-org' placeholder — replace with actual provider.")


_LOCAL_MORPH_EXPECTED: dict[str, int] = {
    "cartethyia": 69, "castorice": 37, "xiangliyao": 70,
}

def _unique_morph_count(character_id: str) -> int:
    """[C6] Compute unique morph names from morph_inventory.json."""
    data = _load(_ROOT / "assets" / "local_characters" / character_id / "morph_inventory.json")
    return len({entry["name"] for entry in data["morphs"]})

class LocalCharacterMorphCountTest(unittest.TestCase):
    """[C6] Verify unique morph counts for three local characters."""

    def test_morph_counts(self) -> None:
        """[C6][subTest] cartethyia:69 castorice:37 xiangliyao:70."""
        for ch, expected in _LOCAL_MORPH_EXPECTED.items():
            with self.subTest(character=ch, expected=expected):
                p = _ROOT / "assets" / "local_characters" / ch / "morph_inventory.json"
                if not p.is_file():
                    self.skipTest(f"{ch}/morph_inventory.json missing")
                self.assertEqual(expected, _unique_morph_count(ch),
                    f"{ch} morph count expected {expected}")

_EXPRESSION_CHARACTERS = ("cartethyia", "castorice", "xiangliyao")

def _existing_nonempty_semantics(manifest: dict[str, Any]) -> set[str]:
    """[C3] Semantic IDs with non-empty channel_map entries in manifest."""
    cm = manifest.get("adapter", {}).get("expression_adapter", {}).get("channel_map", {})
    if not isinstance(cm, dict):
        return set()
    return {k for k, v in cm.items() if isinstance(v, list) and len(v) > 0}

class ExpressionAdapterCandidateTest(unittest.TestCase):
    """[C3] Verify expression_adapter.candidate.json status and non-regression."""

    def test_candidate_status_and_non_regression(self) -> None:
        """[C3][subTest] Candidate basics + non-regression for 3 local characters."""
        if not _has_local_characters():
            self.skipTest("No local character files on this checkout")
        for ch in _EXPRESSION_CHARACTERS:
            with self.subTest(character=ch):
                cp = _ROOT / "assets" / "local_characters" / ch / "expression_adapter.candidate.json"
                if not cp.is_file():
                    self.skipTest(f"{ch} expression_adapter.candidate.json missing")
                data = _load(cp)
                self.assertEqual("candidate", data.get("status"),
                    f"{ch}: status must be 'candidate'")
                self.assertFalse(data.get("has_runtime_regressions", False),
                    f"{ch}: has_runtime_regressions must be false")
                patch = data.get("channel_map_patch", {})
                mp = _ROOT / "assets" / "local_characters" / ch / "character_manifest.json"
                if not mp.is_file():
                    continue
                existing = _existing_nonempty_semantics(_load(mp))
                for sem in existing:
                    self.assertIn(sem, patch,
                        f"{ch}: candidate patch deleted semantic '{sem}'")
                    pl = patch[sem]
                    self.assertTrue(isinstance(pl, list) and len(pl) > 0,
                        f"{ch}: candidate patch downgraded '{sem}' to empty")

class MotionPackageSmokeWalkTest(unittest.TestCase):
    """[C2] Verify smoke_walk motion_package is a fixture, not accepted motion."""

    def test_smoke_walk_is_fixture(self) -> None:
        """[C2] text/source_path must indicate fixture."""
        p = _ROOT / "motion_lab" / "generated" / "library" / "smoke_walk" / "motion_package.json"
        if not p.is_file():
            self.skipTest("smoke_walk motion_package.json not found")
        data = _load(p)
        txt, src = data.get("text", ""), data.get("source_path", "")
        self.assertIn("fixture", f"{txt} {src}".lower(),
            f"smoke_walk must be a fixture; text='{txt}' source='{src}'")

    def test_smoke_walk_status_in_manifest(self) -> None:
        """[C2] status must be pipeline_smoke_test, never accepted/validated."""
        mp = _ROOT / "motion_lab" / "generated" / "motion_library_manifest.json"
        if not mp.is_file():
            self.skipTest("motion_library_manifest.json not found")
        manifest = _load(mp)
        motions = manifest.get("motions", [])
        if not isinstance(motions, list):
            self.skipTest("motion_library_manifest has no motions list")
        smoke = next((m for m in motions if m.get("motion_id") == "smoke_walk"), None)
        if smoke is None:
            self.skipTest("smoke_walk not found in motion_library_manifest")
        status: str = smoke.get("status", "")
        self.assertEqual("pipeline_smoke_test", status,
            f"smoke_walk status must be 'pipeline_smoke_test', got '{status}'")

_PATH_SAFETY_CASES: list[dict[str, str]] = [
    {"repo_rel": "assets/props/polyhaven/polyhaven_manifest.json",
     "path_field": "entry", "id_field": "asset", "may_skip": False},
    {"repo_rel": "data/scene_generation/asset_registry_candidates/"
                 "polyhaven_kitchen_batch_01.json",
     "path_field": "resource_path", "id_field": "asset_id", "may_skip": True},
]
_FORBIDDEN = ("/Users/", "/private/tmp/")

class PolyhavenPathSafetyTest(unittest.TestCase):
    """[S4][O2] Verify all resource paths are res://, not local filesystem paths."""

    def test_all_resource_paths_are_res(self) -> None:
        """[S4][subTest] All entry/resource_path fields must be res://."""
        for c in _PATH_SAFETY_CASES:
            p = _ROOT / c["repo_rel"]
            if c["may_skip"] and not p.is_file():
                continue
            for item in _load(p):
                val: str = item.get(c["path_field"], "")
                aid = item.get(c["id_field"], "?")
                with self.subTest(source=c["repo_rel"].split("/")[-1], asset=aid):
                    self.assertTrue(val.startswith("res://"),
                        f"{aid}: '{val}' not res://")
                    for fb in _FORBIDDEN:
                        self.assertNotIn(fb, val,
                            f"{aid}: '{val}' contains '{fb}'")


class KitchenRegistryStatusTest(unittest.TestCase):
    """[S4] Verify kitchen batch candidates are previewed with valid geometry."""

    def test_kitchen_candidates_previewed_and_valid_geometry(self) -> None:
        """[S4][subTest] status=previewed, AABB positive, source SHA non-empty."""
        p = _ROOT / "data" / "scene_generation" / "asset_registry_candidates" / "polyhaven_kitchen_batch_01.json"
        if not p.is_file():
            self.skipTest("kitchen batch registry json not found")
        items = _load(p)
        expected_ids = {"ceramic_vase_01", "woodenchair_01", "woodentable_01"}
        self.assertIsInstance(items, list, "kitchen batch registry must be a JSON array")
        self.assertEqual(expected_ids, {item.get("asset_id") for item in items},
            "kitchen batch must contain exactly the three golden-path assets")
        for item in items:
            aid = item.get("asset_id", "?")
            with self.subTest(asset=aid):
                self.assertEqual("previewed", item.get("status", ""),
                    f"{aid}: status must be 'previewed'")
                geo = item.get("geometry", {})
                self.assertIsInstance(geo, dict, f"{aid}: geometry must be an object")
                aabb = geo.get("aabb_m", [])
                self.assertIsInstance(aabb, list, f"{aid}: aabb_m must be an array")
                self.assertEqual(3, len(aabb), f"{aid}: aabb_m must have x/y/z")
                for i, d in enumerate(("x", "y", "z")):
                    self.assertIsInstance(aabb[i], (int, float),
                        f"{aid}: aabb_m.{d} must be numeric")
                    self.assertGreater(aabb[i], 0,
                        f"{aid}: aabb_m.{d}={aabb[i]} must be positive")
                sha = item.get("provenance", {}).get("source_sha256", "")
                self.assertTrue(isinstance(sha, str) and len(sha) > 0,
                    f"{aid}: source_sha256 must be non-empty")


if __name__ == "__main__":
    unittest.main()
