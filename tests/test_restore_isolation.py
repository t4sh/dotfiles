"""Run the portable PowerShell wrapper fixture when PowerShell is available."""
from pathlib import Path
import shutil
import subprocess
import unittest


class RestoreIsolation(unittest.TestCase):
    @unittest.skipUnless(shutil.which("pwsh"), "PowerShell required for wrapper execution")
    def test_restore_isolation(self):
        result = subprocess.run(
            [shutil.which("pwsh"), "-NoLogo", "-NoProfile", "-File",
             str(Path(__file__).with_name("test_windows_restore_isolation.ps1"))],
            text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("30 cases", result.stdout)


if __name__ == "__main__":
    unittest.main()
