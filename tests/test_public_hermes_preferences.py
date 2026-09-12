"""Public-owned Hermes fixtures: synthetic preferences, no installed app access."""
import importlib.util
import io
import os
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "scripts/hermes-settings.py"

spec = importlib.util.spec_from_file_location("public_hermes_settings", HELPER)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)

class HermesSkillBoundary(unittest.TestCase):
    def test_skill_boundary_reports_scan_errors_instead_of_clean(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            skills = home / ".hermes/skills"
            skills.mkdir(parents=True)
            with patch.object(helper.Path, "home", return_value=home):
                with patch.object(helper.os, "scandir", side_effect=PermissionError("fixture access denied")):
                    with self.assertRaisesRegex(PermissionError, "access denied"):
                        helper.check_skill_boundary(skills.parent / "config.yaml")
                    with self.assertRaisesRegex(PermissionError, "access denied"):
                        helper.shared_skill_aliases(skills.parent / "config.yaml")

    def test_skill_boundary_accepts_missing_root_but_rejects_a_file(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            profile = home / ".hermes"
            profile.mkdir()
            with patch.object(helper.Path, "home", return_value=home):
                helper.check_skill_boundary(profile / "config.yaml")
                (profile / "skills").write_text("unexpected file", encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "must be a directory"):
                    helper.check_skill_boundary(profile / "config.yaml")

    def test_skill_isolation_preserves_shared_files_and_confines_later_bundle_writes(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            shared = home / ".agents/skills/research"
            shared.mkdir(parents=True)
            skill = shared / "SKILL.md"
            skill.write_text("personal research", encoding="utf-8")
            local = home / ".hermes/skills"
            local.mkdir(parents=True)
            alias = local / "research"
            if sys.platform == "win32":
                subprocess.run(["cmd", "/c", "mklink", "/J", str(alias), str(shared)], check=True, capture_output=True)
            else:
                alias.symlink_to(shared, target_is_directory=True)
            live = local.parent / "config.yaml"
            live.write_text(json.dumps({"skills": {"external_dirs": [str(shared.parent)]}}), encoding="utf-8")
            before = skill.read_bytes()
            try:
                with patch.object(helper.Path, "home", return_value=home):
                    with self.assertRaisesRegex(ValueError, "directory alias"):
                        helper.check_skill_boundary(live)
                    helper.isolate_shared_skills(live)
                    helper.isolate_shared_skills(live)
                    helper.check_skill_boundary(live)
                self.assertEqual(skill.read_bytes(), before)
                self.assertTrue(os.path.lexists(local.parent / "skill-alias-backups/research"))
                alias.mkdir()
                (alias / "DESCRIPTION.md").write_text("Hermes category", encoding="utf-8")
                self.assertFalse((shared / "DESCRIPTION.md").exists())
                self.assertEqual(skill.read_bytes(), before)
            finally:
                # Explicitly remove only the fixture link/junction before temp cleanup.
                for candidate in (alias, local.parent / "skill-alias-backups/research"):
                    if candidate.is_symlink():
                        candidate.unlink()
                    elif getattr(candidate, "is_junction", lambda: False)():
                        candidate.rmdir()

    def test_skill_isolation_requires_external_discovery_and_preserves_real_directories(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            local = home / ".hermes/skills/research"
            local.mkdir(parents=True)
            owned = local / "SKILL.md"
            owned.write_text("Hermes-owned skill", encoding="utf-8")
            live = local.parent.parent / "config.yaml"
            live.write_text('{"skills": {"create_dir": "~/.agents/skills"}}', encoding="utf-8")
            with patch.object(helper.Path, "home", return_value=home):
                with self.assertRaisesRegex(ValueError, "external_dirs"):
                    helper.isolate_shared_skills(live)
                helper.check_skill_boundary(live)
            self.assertEqual(owned.read_text(encoding="utf-8"), "Hermes-owned skill")

    @unittest.skipIf(sys.platform == "win32", "POSIX symlink fixture; junction migration covered separately")
    def test_skill_boundary_blocks_restore_and_preserves_conflicting_backup(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            shared = home / ".agents/skills/research"
            shared.mkdir(parents=True)
            local = home / ".hermes/skills"
            local.mkdir(parents=True)
            alias = local / "research"
            alias.symlink_to(shared, target_is_directory=True)
            live = local.parent / "config.yaml"
            live.write_text(json.dumps({"skills": {"external_dirs": [str(shared.parent)]}}), encoding="utf-8")
            before = live.read_bytes()
            backup = local.parent / "skill-alias-backups/research"
            backup.parent.mkdir()
            backup.write_text("existing backup", encoding="utf-8")
            args = ["hermes-settings", "restore", "--skills-only", "--live", str(live),
                    "--snapshot", str(ROOT / "apps/windows/hermes/config.json")]
            with patch.object(helper.Path, "home", return_value=home):
                with patch.object(sys, "argv", args), patch("sys.stdout", new_callable=io.StringIO):
                    self.assertEqual(helper.main(), 1)
                with self.assertRaisesRegex(ValueError, "backup already exists"):
                    helper.isolate_shared_skills(live)
            self.assertEqual(live.read_bytes(), before)
            self.assertTrue(alias.is_symlink())
            self.assertEqual(backup.read_text(encoding="utf-8"), "existing backup")

    @unittest.skipIf(sys.platform == "win32", "POSIX symlink fixture")
    def test_skill_boundary_refuses_aliased_profile_root(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            shared = home / ".agents/skills"
            shared.mkdir(parents=True)
            profile = home / ".hermes"
            profile.mkdir()
            (profile / "skills").symlink_to(shared, target_is_directory=True)
            with patch.object(helper.Path, "home", return_value=home):
                with self.assertRaisesRegex(ValueError, "skills root"):
                    helper.check_skill_boundary(profile / "config.yaml")


class HermesPreferences(unittest.TestCase):
    def run_helper(self, mode, live, snapshot, *options):
        return subprocess.run([sys.executable, str(HELPER), mode, "--live", str(live),
            "--snapshot", str(snapshot), *options], capture_output=True, text=True)

    def test_capture_resume_without_auth(self):
        with tempfile.TemporaryDirectory() as folder:
            live, saved = Path(folder)/"config.json", Path(folder)/"snapshot.json"
            live.write_text(json.dumps({"model": {"default": "fixture/model"},
                "display": {"resume_last_session": False}, "auth": {"fixture": "not-a-real-credential"}}))
            result = self.run_helper("capture", live, saved)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(saved.read_text()), {"model": {"default": "fixture/model"},
                "display": {"resume_last_session": False}})

    def test_preserve_model_and_add_skills_idempotently(self):
        with tempfile.TemporaryDirectory() as folder:
            live, saved = Path(folder)/"config.json", Path(folder)/"snapshot.json"
            original = {"default": "fixture/local", "provider": "fixture", "base_url": "https://example.invalid/v1?api-version=fixture"}
            live.write_text(json.dumps({"model": original, "skills": {"external_dirs": ["profile-skills"]}, "unmanaged": True}))
            saved.write_text(json.dumps({"model": {"default": "fixture/saved", "aliases": {"sample": "fixture/alias"}},
                "display": {"resume_last_session": False}, "skills": {"create_dir": "~/.agents/skills", "external_dirs": ["~/.agents/skills"]}}))
            for _ in range(2):
                result = self.run_helper("restore", live, saved, "--preserve-model-selection")
                self.assertEqual(result.returncode, 0, result.stderr)
            actual = json.loads(live.read_text())
            self.assertEqual(actual["model"], dict(original, aliases={"sample": "fixture/alias"}))
            self.assertTrue(actual["unmanaged"])
            self.assertEqual(actual["skills"]["external_dirs"], ["profile-skills", "~/.agents/skills"])
            result = self.run_helper("check", live, saved, "--preserve-model-selection")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotEqual(self.run_helper("check", live, saved).returncode, 0)

    def test_preserved_missing_model_and_snapshot_validation(self):
        with tempfile.TemporaryDirectory() as folder:
            live, saved = Path(folder)/"config.json", Path(folder)/"snapshot.json"
            live.write_text(json.dumps({"display": {"resume_last_session": False}}))
            saved.write_text(json.dumps({"model": {"default": "fixture/saved"},
                "display": {"resume_last_session": False}}))
            result = self.run_helper("check", live, saved, "--preserve-model-selection")
            self.assertEqual(result.returncode, 0, result.stderr)
            # The option excludes live model fields, never saved-snapshot validation.
            saved.write_text(json.dumps({"model": {"default": "fixture/saved",
                "base_url": "https://example.invalid/v1?fixture=invalid-snapshot"}}))
            before = live.read_bytes()
            result = self.run_helper("restore", live, saved, "--preserve-model-selection")
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(live.read_bytes(), before)

    def test_public_template_is_skills_only(self):
        saved = ROOT / "apps/windows/hermes/config.json"
        self.assertEqual(json.loads(saved.read_text()), {"skills": {"create_dir": "~/.agents/skills", "external_dirs": ["~/.agents/skills"]}})
        with tempfile.TemporaryDirectory() as folder:
            live = Path(folder)/"config.json"
            live.write_text(json.dumps({"model": {"default": "fixture/unchanged"}, "display": {"skin": "fixture"}}))
            result = self.run_helper("restore", live, saved, "--skills-only")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(live.read_text())["model"]["default"], "fixture/unchanged")
            result = self.run_helper("capture", live, Path(folder)/"invalid.json", "--preserve-model-selection")
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((Path(folder)/"invalid.json").exists())

if __name__ == "__main__":
    unittest.main()
