import json
import os
import shlex
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ClaudeRtkHookTests(unittest.TestCase):
    client = "claude"
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        home = Path(self.temp.name)
        self.settings = home / (".codex/hooks.json" if self.client == "codex" else ".claude/settings.json")
        self.rtk = home / "bin/rtk"
        self.rtk.parent.mkdir()
        self.rtk.write_text("#!/bin/sh\n")
        self.rtk.chmod(0o755)
        self.command = shlex.join([str(self.rtk), "hook", self.client])

    def run_helper(self, action, success=True, rtk=None):
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts/rtk-hook.py"), action, "--client", self.client,
             "--settings", str(self.settings), "--rtk", str(rtk or self.rtk)],
            capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def rtk_entry(self):
        entry = {"type": "command", "command": self.command}
        if self.client == "codex":
            entry["statusMessage"] = "RTK command compression"
        return {"matcher": "Bash", "hooks": [entry]}

    def test_restore_initializes_missing_settings(self):
        self.run_helper("check", success=False)
        self.run_helper("restore")
        self.assertEqual(json.loads(self.settings.read_text()),
                         {"hooks": {"PreToolUse": [self.rtk_entry()]}})
        self.run_helper("check")

    def test_merge_preserves_unmanaged_values_and_is_idempotent(self):
        other = {"matcher": "Edit", "hooks": [{"type": "command", "command": "lint"}]}
        self.settings.parent.mkdir()
        self.settings.write_text(json.dumps({
            "theme": "auto", "permissions": {"allow": ["Bash(ls)"]},
            "hooks": {"PreToolUse": [other], "Stop": [{"hooks": []}]}}))
        self.run_helper("restore")
        after = json.loads(self.settings.read_text())
        self.assertEqual(after["theme"], "auto")
        self.assertEqual(after["permissions"], {"allow": ["Bash(ls)"]})
        self.assertEqual(after["hooks"]["Stop"], [{"hooks": []}])
        self.assertEqual(after["hooks"]["PreToolUse"], [other, self.rtk_entry()])
        stamp = self.settings.stat().st_mtime_ns
        self.run_helper("restore")
        self.assertEqual(self.settings.stat().st_mtime_ns, stamp)
        self.run_helper("check")

    def test_stale_and_duplicate_entries_collapse_to_one(self):
        shared = {"matcher": "Bash", "hooks": [
            {"type": "command", "command": "guard"},
            {"type": "command", "command": f"/usr/local/bin/rtk hook {self.client}"}]}
        self.settings.parent.mkdir()
        self.settings.write_text(json.dumps({"hooks": {"PreToolUse": [
            shared, {"matcher": "Bash", "hooks": [{"type": "command", "command": f"rtk hook {self.client}"}]}]}}))
        self.run_helper("check", success=False)
        self.run_helper("restore")
        groups = json.loads(self.settings.read_text())["hooks"]["PreToolUse"]
        self.assertEqual(groups, [
            {"matcher": "Bash", "hooks": [{"type": "command", "command": "guard"}]},
            self.rtk_entry()])
        self.run_helper("check")

    def test_symlinked_settings_stay_linked(self):
        target = Path(self.temp.name) / "managed.json"
        target.write_text("{}")
        self.settings.parent.mkdir()
        self.settings.symlink_to(target)
        self.run_helper("restore")
        self.assertTrue(self.settings.is_symlink())
        self.assertIn(self.command, target.read_text())

    def test_malformed_settings_and_missing_rtk_fail_without_writing(self):
        self.settings.parent.mkdir()
        self.settings.write_text('{"secret": "do-not-print"')
        result = self.run_helper("restore", success=False)
        self.assertNotIn("do-not-print", result.stdout + result.stderr)
        self.assertEqual(self.settings.read_text(), '{"secret": "do-not-print"')
        self.settings.write_text("{}")
        self.run_helper("restore", success=False, rtk=Path(self.temp.name) / "missing")
        self.assertEqual(self.settings.read_text(), "{}")


    def test_path_resolution_and_quoted_executable(self):
        executable = Path(self.temp.name) / "Intel Homebrew/bin/rtk"
        executable.parent.mkdir(parents=True)
        executable.write_text("#!/bin/sh\n")
        executable.chmod(0o755)
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts/rtk-hook.py"), "restore", "--client", self.client,
             "--settings", str(self.settings)],
            env={**os.environ, "PATH": str(executable.parent)}, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        entry = json.loads(self.settings.read_text())["hooks"]["PreToolUse"][0]["hooks"][0]
        self.assertEqual(shlex.split(entry["command"]), [str(executable), "hook", self.client])
        self.run_helper("check", rtk=executable)


class CodexRtkHookTests(ClaudeRtkHookTests):
    client = "codex"

    def test_legacy_dotfiles_link_migrates_without_changing_source(self):
        repo = Path(self.temp.name) / "repo"
        helper = repo / "scripts/rtk-hook.py"
        helper.parent.mkdir(parents=True)
        shutil.copyfile(ROOT / "scripts/rtk-hook.py", helper)
        source = repo / "config/codex/hooks.json"
        source.parent.mkdir(parents=True)
        original = json.dumps({"hooks": {"Stop": [{"hooks": []}]}})
        source.write_text(original)
        self.settings.parent.mkdir()
        self.settings.symlink_to(source)
        result = subprocess.run(
            [sys.executable, str(helper), "restore", "--client", "codex",
             "--settings", str(self.settings), "--rtk", str(self.rtk)],
            capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.settings.is_symlink())
        self.assertEqual(source.read_text(), original)
        self.assertEqual(json.loads(self.settings.read_text())["hooks"]["Stop"], [{"hooks": []}])
        self.run_helper("check")


if __name__ == "__main__":
    unittest.main()
