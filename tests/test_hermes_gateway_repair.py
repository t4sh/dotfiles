"""Exercise gateway repair against an isolated checkout and a one-file patch."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(sys.platform == "darwin", "macOS Hermes maintenance")
class GatewayRepairTest(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location("repair", ROOT / "scripts/repair-hermes-gateway.py")
        self.repair = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.repair)
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.runtime = self.root / self.repair.RUNTIME
        self.runtime.parent.mkdir()
        self.runtime.write_text("original\n")
        self.git("init", "-q")
        self.git("add", self.repair.RUNTIME)
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                 "-c", "commit.gpgSign=false", "-c", "core.hooksPath=/dev/null",
                 "commit", "-qm", "Fixture baseline")
        self.runtime.write_text("fixed\n")
        self.repair.PATCH = self.root / "fixture.patch"
        self.repair.PATCH.write_text(self.git("diff", "--no-ext-diff", "--", self.repair.RUNTIME))
        self.runtime.write_text("original\n")

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.root), *args], text=True)

    def invoke(self, *args):
        with patch.object(sys, "argv", ["repair", "--hermes-root", str(self.root), *args]):
            self.repair.main()

    def test_loss_on_update_and_repeat_repair(self):
        with self.assertRaisesRegex(SystemExit, "missing"):
            self.invoke("--check")
        for _ in range(2):
            self.invoke()
            self.invoke("--check")
            self.assertEqual(self.runtime.read_text(), "fixed\n")
        self.assertEqual(self.git("diff", "--cached"), "")

    def test_local_edit_and_concurrent_update(self):
        self.runtime.write_text("user edit\n")
        with self.assertRaisesRegex(SystemExit, "Local edits"):
            self.invoke()
        self.assertEqual(self.runtime.read_text(), "user edit\n")
        self.runtime.write_text("original\n")
        import fcntl
        with (self.root / ".git/hermes-update.lock").open("a+b") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            with self.assertRaisesRegex(SystemExit, "update is running"):
                self.invoke()
        self.assertEqual(self.runtime.read_text(), "original\n")

    def test_incompatible_release(self):
        self.repair.PATCH.write_text(self.repair.PATCH.read_text().replace("-original\n", "-obsolete\n"))
        with self.assertRaisesRegex(SystemExit, "Review the gateway patch"):
            self.invoke()
        self.assertEqual(self.runtime.read_text(), "original\n")


if __name__ == "__main__":
    unittest.main()
