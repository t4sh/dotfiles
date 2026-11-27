import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import os
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("zed_check", ROOT / "scripts/check-zed.py")
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class ZedCheckTests(unittest.TestCase):
    def test_repository_snapshots_parse(self):
        self.assertEqual(checker.check(ROOT, ROOT / "apps/zed", ROOT / "unused", True), [])

    def test_preference_audit_rejects_malformed_zed_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            settings = root / "apps/zed/settings.json"
            settings.parent.mkdir(parents=True)
            settings.write_text('{"cursor_animation":{"enabled":true}},"theme":{}\n')
            bash = "bash"
            if os.name == "nt":
                # The Windows system bash.exe is WSL, not Git for Windows.
                git = shutil.which("git")
                self.assertIsNotNone(git, "Git for Windows is required")
                bash = str(Path(git).resolve().parents[1] / "bin/bash.exe")
                self.assertTrue(Path(bash).is_file(), "Git Bash is required")
            result = subprocess.run(
                [bash, (ROOT / "scripts/audit-app-prefs.sh").as_posix()],
                env={**os.environ, "DOTFILES": root.as_posix()}, capture_output=True, text=True,
            )
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("invalid Zed JSONC", result.stdout + result.stderr)
            settings.write_text('{"theme": "One Dark"}\n')
            (settings.parent / "keymap.json").write_text('[// shortcuts\n]\n')
            valid = subprocess.run(
                [bash, (ROOT / "scripts/audit-app-prefs.sh").as_posix()],
                env={**os.environ, "DOTFILES": root.as_posix()}, capture_output=True, text=True,
            )
            self.assertEqual(valid.returncode, 0, valid.stdout + valid.stderr)

    def test_repository_snapshot_parses_as_a_single_settings_object(self):
        settings = checker.read_settings(ROOT / "apps/zed/settings.json")
        self.assertIsInstance(settings, dict)
        self.assertIn("agent_servers", settings)

    def test_settings_alone_do_not_prove_extension_or_theme_readiness(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo = root / "repo"
            snapshot = repo / "apps/zed"
            snapshot.mkdir(parents=True)
            live = root / "live"
            live.mkdir()
            extensions = root / "extensions"
            settings = {"theme": {"dark": "Fixture Dark", "light": "One Light"},
                        "auto_install_extensions": {"fixture": True}}
            for folder in (snapshot, live):
                (folder / "settings.json").write_text(json.dumps(settings))
                (folder / "keymap.json").write_text("[]")
            self.assertEqual(checker.check(repo, live, extensions, True), [])
            self.assertEqual(len(checker.check(repo, live, extensions)), 2)
            package = extensions / "fixture"
            (package / "themes").mkdir(parents=True)
            (package / "extension.toml").write_text('id = "fixture"\n')
            self.assertEqual(checker.check(repo, live, extensions),
                             ["Missing selected theme resource: Fixture Dark"])
            (package / "themes/theme.json").write_text('{"themes":[{"name":"Fixture Dark"}]}')
            self.assertEqual(checker.check(repo, live, extensions), [])
            settings["theme"]["dark"] = "Other Theme"
            (live / "settings.json").write_text(json.dumps(settings))
            self.assertIn("Managed settings differ", checker.check(repo, live, extensions)[0])

    def test_local_agent_options_do_not_mask_managed_drift(self):
        expected = {"agent_servers": {"codex-acp": {"type": "registry"}}}
        actual = {"agent_servers": {"codex-acp": {"type": "registry", "local_option": "fixture"}}}
        self.assertTrue(checker.managed_matches(expected, actual))
        actual["agent_servers"]["codex-acp"]["type"] = "custom"
        self.assertFalse(checker.managed_matches(expected, actual))


if __name__ == "__main__":
    unittest.main()
