import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SAVED = {"attribution": {"attributeCommitsToAgent": False, "attributePRsToAgent": False}}


class CursorCliSettingsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.live = self.home / ".cursor/cli-config.json"
        self.live.parent.mkdir()
        self.saved = self.home / "snapshot.json"
        self.saved.write_text(json.dumps(SAVED))

    def run_helper(self, action, success=True):
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts/cursor-cli-settings.py"), action,
             "--live", str(self.live), "--snapshot", str(self.saved)],
            capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def test_merge_preserves_unmanaged_values_and_is_idempotent(self):
        before = {"version": 1, "model": {"id": "fixture"},
                  "privateFixture": "do-not-capture",
                  "attribution": {"other": "preserve", "attributePRsToAgent": True}}
        self.live.write_text(json.dumps(before))
        self.run_helper("restore")
        after = json.loads(self.live.read_text())
        expected = {**before, "attribution": {**before["attribution"], **SAVED["attribution"]}}
        self.assertEqual(after, expected)
        stamp = self.live.stat().st_mtime_ns
        self.run_helper("restore")
        self.assertEqual(self.live.stat().st_mtime_ns, stamp)
        self.run_helper("check")
        self.run_helper("capture")
        self.assertEqual(json.loads(self.saved.read_text()), SAVED)
        self.assertNotIn("do-not-capture", self.saved.read_text())

    def test_missing_live_retains_backup_and_restore_initializes(self):
        previous = self.saved.read_bytes()
        self.run_helper("capture")
        self.assertEqual(self.saved.read_bytes(), previous)
        self.run_helper("restore")
        self.assertEqual(json.loads(self.live.read_text()), {"version": 1, **SAVED})

    def test_defaults_and_explicit_values_are_captured(self):
        self.live.write_text('{"attribution": {"attributePRsToAgent": false}}')
        self.run_helper("check", success=False)
        self.run_helper("capture")
        self.assertEqual(json.loads(self.saved.read_text()), {
            "attribution": {"attributeCommitsToAgent": True, "attributePRsToAgent": False}})

    def test_invalid_live_does_not_modify_either_file(self):
        for invalid in ('{"privateFixture": "do-not-print",', '[]',
                        '{"attribution": null}', '{"attribution": {"attributePRsToAgent": "false"}}'):
            with self.subTest(invalid=invalid):
                self.live.write_text(invalid)
                previous = self.saved.read_bytes()
                for action in ("capture", "restore"):
                    result = self.run_helper(action, success=False)
                    self.assertNotIn("do-not-print", result.stderr)
                    self.assertEqual(self.live.read_text(), invalid)
                    self.assertEqual(self.saved.read_bytes(), previous)

    def test_snapshot_rejects_extra_fields_before_restore(self):
        self.saved.write_text(json.dumps({**SAVED, "privateFixture": "do-not-capture"}))
        self.run_helper("audit", success=False)
        self.run_helper("restore", success=False)
        self.assertFalse(self.live.exists())

    def test_targeted_make_restore_uses_live_home(self):
        result = subprocess.run(["make", "restore-cursor-cli", "cursor-cli-check"], cwd=ROOT,
                                env={**os.environ, "HOME": str(self.home), "DOTFILES": str(ROOT)},
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(self.live.read_text())["attribution"], SAVED["attribution"])

    @unittest.skipIf(os.name == "nt", "POSIX symlink fixture")
    def test_restore_preserves_live_symlink(self):
        target = self.home / "real.json"
        target.write_text('{}')
        self.live.symlink_to(target)
        self.run_helper("restore")
        self.assertTrue(self.live.is_symlink())
        self.assertEqual(json.loads(target.read_text()), SAVED)


if __name__ == "__main__":
    unittest.main()
