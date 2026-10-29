import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SAVED = json.loads((ROOT / "config/claude/settings.json").read_text())


class ClaudeSettingsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.live = Path(self.temp.name) / ".claude/settings.json"
        self.live.parent.mkdir()

    def run_helper(self, action, success=True):
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts/claude-settings.py"), action,
             "--settings", str(self.live)],
            capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def test_merge_preserves_unmanaged_values_and_is_idempotent(self):
        before = {"theme": "dark", "hooks": {"PreToolUse": []},
                  "attribution": {"commit": "x"}, "includeCoAuthoredBy": True}
        self.live.write_text(json.dumps(before))
        self.run_helper("check", success=False)
        self.run_helper("restore")
        self.assertEqual(json.loads(self.live.read_text()), {**before, **SAVED})
        stamp = self.live.stat().st_mtime_ns
        self.run_helper("restore")
        self.assertEqual(self.live.stat().st_mtime_ns, stamp)
        self.run_helper("check")

    def test_restore_creates_missing_settings(self):
        self.run_helper("restore")
        self.assertEqual(json.loads(self.live.read_text()), SAVED)

    def test_invalid_live_settings_are_left_untouched(self):
        self.live.write_text('["private"]')
        result = self.run_helper("restore", success=False)
        self.assertNotIn("private", result.stdout + result.stderr)
        self.assertEqual(self.live.read_text(), '["private"]')


if __name__ == "__main__":
    unittest.main()
