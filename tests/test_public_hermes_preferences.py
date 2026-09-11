"""Public-owned Hermes fixtures: synthetic preferences, no installed app access."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "scripts/hermes-settings.py"

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
            original = {"default": "fixture/local", "provider": "fixture", "base_url": "https://example.invalid/v1"}
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
