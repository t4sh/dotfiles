"""Exact false-positive exceptions must survive LF and CRLF without widening."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("gitleaks"), "gitleaks not installed")
class GitleaksPortabilityTests(unittest.TestCase):
    def test_icon_exception_is_exact_and_path_scoped_for_both_line_endings(self):
        icon = b"EAAA" + b"hCAAAQgAIGJCZS1I2zk3WKXtUtsZL8hnbjrOVD0MPnj"
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            path = root / "services/Open in Tower.workflow/Contents/document.wflow"
            path.parent.mkdir(parents=True)
            for ending in (b"\n", b"\r\n"):
                for name, target, payload, expected in (
                    ("exact icon", path, icon, 0),
                    ("changed icon", path, icon[:-1] + b"k", 7),
                    ("wrong file", root / "elsewhere.txt", icon, 7),
                ):
                    with self.subTest(ending=ending, case=name):
                        target.write_bytes(payload + ending)
                        result = subprocess.run(
                            ["gitleaks", "dir", str(root), "--no-banner", "--redact",
                             "--config", str(ROOT / ".gitleaks.toml"), "--exit-code", "7"],
                            capture_output=True, text=True)
                        target.unlink()
                        self.assertEqual(result.returncode, expected,
                                         result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
