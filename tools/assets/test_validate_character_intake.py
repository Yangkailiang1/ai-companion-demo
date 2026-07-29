"""Tests for character intake validator.

Roadmap: O2.2
Responsibility: Exercise the validate_character_intake CLI with tempfile fixtures;
never writes outside temporary directories.
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest


CLI = os.path.join(os.path.dirname(os.path.abspath(__file__)), "validate_character_intake.py")

SHA_VALID = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
SHA_OTHER = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"


class TestValidateCharacterIntake(unittest.TestCase):
    """[O2.2] Test runner for character intake validator."""

    def setUp(self) -> None:
        """[O2.2] Create fixture root; side effects: creates a temp directory."""
        self.tmp = tempfile.TemporaryDirectory()
        self.pr = self.tmp.name
        # Ensure project root is a directory
        os.makedirs(self.pr, exist_ok=True)

    def tearDown(self) -> None:
        """[O2.2] Clean fixtures; side effects: deletes the temp directory."""
        self.tmp.cleanup()

    # -- helpers --------------------------------------------------------------

    def _write(self, relpath: str, content: object) -> str:
        """[O2.2] Write a fixture; side effects: creates files and directories."""
        full = os.path.join(self.pr, relpath)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w", encoding="utf-8") as fh:
            if isinstance(content, (dict, list)):
                json.dump(content, fh)
            else:
                fh.write(content)
        return full

    def _run(self, intake_data: dict, **kwargs: object) -> subprocess.CompletedProcess:
        """[O2.2] Invoke CLI; side effects: writes intake and starts subprocess."""
        intake_path = os.path.join(self.pr, "intake.json")
        with open(intake_path, "w", encoding="utf-8") as fh:
            json.dump(intake_data, fh)
        cmd = [sys.executable, CLI, intake_path, "--project-root", self.pr]
        return subprocess.run(cmd, capture_output=True, text=True)

    def _default_intake(self, **overrides: object) -> dict:
        """[O2.2] Build valid intake data; side effects: none."""
        data = {
            "schema_version": 1,
            "character_id": "test_char",
            "classification": "local_only",
            "status": "inventoried",
            "model_path": "res://model.glb",
            "provenance_path": "res://provenance.json",
            "inventories": {
                "bones": "res://bones.json",
                "morphs": "res://morphs.json",
                "animations": "res://anims.json",
            },
            "source_sha256": SHA_VALID,
        }
        data.update(overrides)
        return data

    def _fill_local_only(self, sha: str = SHA_VALID) -> None:
        """[O2.2] Create local fixtures; side effects: writes package files."""
        self._write("model.glb", "dummy")
        self._write("provenance.json", {
            "redistribution": "local_only",
            "license": "unknown",
            "source_sha256": sha,
        })
        self._write("bones.json", {"bones": []})
        self._write("morphs.json", {"morphs": []})
        self._write("anims.json", {"animations": []})

    def _fill_public(self) -> None:
        """[O2.2] Create public fixtures; side effects: writes package files."""
        self._write("model.glb", "dummy")
        self._write("provenance.json", {
            "redistribution": "allowed",
            "license": "CC0",
            "source_sha256": SHA_VALID,
        })
        self._write("bones.json", {"bones": []})
        self._write("morphs.json", {"morphs": []})
        self._write("anims.json", {"animations": []})

    # -- tests ----------------------------------------------------------------

    def test_01_valid_local_only(self) -> None:
        """[O2.2] Accept local-only package; side effects: runs CLI subprocess."""
        self._fill_local_only()
        r = self._run(self._default_intake())
        self.assertEqual(r.returncode, 0, f"stderr: {r.stderr}")
        self.assertIn("CHARACTER_INTAKE_PASS", r.stdout)

    def test_02_valid_public(self) -> None:
        """[O2.2] Accept public package; side effects: runs CLI subprocess."""
        self._fill_public()
        intake = self._default_intake(
            classification="public_redistributable",
            status="downloaded",
        )
        r = self._run(intake)
        self.assertEqual(r.returncode, 0, f"stderr: {r.stderr}")
        self.assertIn("CHARACTER_INTAKE_PASS", r.stdout)

    def test_03_unknown_license_rejected_for_public(self) -> None:
        """[O2.2] Reject unknown public license; side effects: runs CLI."""
        self._fill_local_only()  # license=unknown, redistribution=local_only
        intake = self._default_intake(
            classification="public_redistributable",
            status="downloaded",
        )
        r = self._run(intake)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("license", r.stderr.lower())

    def test_04_redistribution_mismatch(self) -> None:
        """[O2.2] Reject redistribution mismatch; side effects: runs CLI."""
        self._fill_public()  # redistribution=allowed
        intake = self._default_intake(
            classification="local_only",
            status="inventoried",
        )
        r = self._run(intake)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("redistribution", r.stderr.lower())

    def test_05_sha_mismatch(self) -> None:
        """[O2.2] Reject SHA mismatch; side effects: runs CLI."""
        self._fill_local_only(sha=SHA_OTHER)
        intake = self._default_intake(source_sha256=SHA_VALID)
        r = self._run(intake)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("source_sha256 mismatch", r.stderr)

    def test_06_missing_referenced_file(self) -> None:
        """[O2.2] Reject missing file; side effects: runs CLI."""
        self._fill_local_only()
        intake = self._default_intake(model_path="res://nonexistent.glb")
        r = self._run(intake)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("file not found", r.stderr)

    def test_07_path_traversal_and_machine_path(self) -> None:
        """[O2.2] Reject unsafe paths; side effects: runs CLI subprocesses."""
        self._fill_local_only()

        # path traversal
        r = self._run(self._default_intake(model_path="res://../secret/model.glb"))
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("path traversal", r.stderr)

        # absolute machine path
        r = self._run(self._default_intake(model_path="/etc/passwd"))
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("must start with res://", r.stderr)

        r = self._run(self._default_intake(model_path=r"res://..\secret.glb"))
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("backslash", r.stderr)

        os.symlink("/etc", os.path.join(self.pr, "outside"))
        r = self._run(self._default_intake(model_path="res://outside/passwd"))
        self.assertIn("escapes project root", r.stderr)

    def test_08_rejected_cross_field(self) -> None:
        """[O2.2] Enforce rejected state rules; side effects: runs CLI."""
        self._fill_local_only()

        # rejected classification with wrong status
        r = self._run(self._default_intake(
            classification="rejected", status="inventoried",
        ))
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("rejected", r.stderr)

        # non-rejected classification with status=rejected
        r = self._run(self._default_intake(
            classification="local_only", status="rejected",
        ))
        self.assertNotEqual(r.returncode, 0)

        self._write("bones.json", "{not-json")
        r = self._run(self._default_intake(
            classification="rejected", status="rejected",
        ))
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("inventories.bones", r.stderr)

    def test_09_real_penguin_intake_passes(self) -> None:
        """[O2.2] Validate real intake; side effects: runs CLI subprocess."""
        repo_root = os.path.abspath(
            os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
        )
        intake_path = os.path.join(
            repo_root, "assets", "characters", "penguin", "character_intake.json",
        )
        cmd = [sys.executable, CLI, intake_path, "--project-root", repo_root]
        r = subprocess.run(cmd, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, f"stderr: {r.stderr}")
        self.assertIn("CHARACTER_INTAKE_PASS", r.stdout)


if __name__ == "__main__":
    unittest.main()
