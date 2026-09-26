"""Public macOS preference boundary: policy is portable, personal capture is private."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(sys.platform == "darwin", "macOS workflow")
class PublicMacPreferences(unittest.TestCase):
    def test_personal_capture_refused_before_reading_preferences(self):
        with tempfile.TemporaryDirectory() as temporary:
            snapshot = Path(temporary) / "personal.json"
            env = {**os.environ, "DOTFILES_PUBLIC_SNAPSHOT": "1",
                   "DOTFILES_MACOS_PREFERENCES": str(snapshot)}
            result = subprocess.run([sys.executable, str(ROOT / "scripts/macos-preferences.py"), "capture"],
                                    env=env, text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("private-only", result.stderr)
            self.assertFalse(snapshot.exists())

    def test_keyboard_policy_and_major_mapping(self):
        spec = importlib.util.spec_from_file_location("mac_preferences", ROOT / "scripts/macos-preferences.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        policy = (ROOT / "config/macos-preferences.tsv").read_text()
        for key in ("KeyRepeat", "InitialKeyRepeat", "AppleKeyboardUIMode"):
            self.assertIn(key, policy)
        self.assertIn("AppleFnUsageType", (ROOT / "macos/KEYBOARD.md").read_text())
        self.assertEqual(module.actual_key("@FocusModes", 26), "NSStatusItem VisibleCC FocusModes")
        self.assertEqual(module.actual_key("@FocusModes", 27), "NSStatusItem VisibleCC FocusModes")
        self.assertEqual(module.actual_key("@FocusModes", 15), "NSStatusItem Visible FocusModes")


if __name__ == "__main__":
    unittest.main()
