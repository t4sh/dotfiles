#!/usr/bin/env python3
"""On-demand TypeSafe runner fixtures using disposable credentials."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[1]
def run(*args, **kwargs):
    kwargs.setdefault("stdin", subprocess.DEVNULL)
    return subprocess.run(args, text=True, capture_output=True, **kwargs)

class TypeSafeEnvTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="typesafe-env-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.secrets = self.root / "secrets"
        self.credential = self.secrets / "config/env/typesafe.env"
        self.env = {**os.environ, "DOTFILES_SECRETS_DIR": str(self.secrets)}
        self.env.pop("TYPESAFE_API_KEY", None)
        self.env.pop("TYPESAFE_FIXTURE_UNRELATED", None)

    def invoke(self, *args: str, trace: bool = False):
        return run(
            "bash", *(["-x"] if trace else []), str(ROOT / "bin/typesafe-env"),
            *args, env=self.env, cwd=self.root,
        )

    def write_credential(self, content: str) -> None:
        self.credential.parent.mkdir(parents=True, exist_ok=True)
        self.credential.write_text(content)

    def test_init_is_private_and_preserves_existing_content(self) -> None:
        created = self.invoke("--init")
        self.assertEqual(created.returncode, 0, created.stderr)
        self.assertEqual(self.credential.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.credential.parent.stat().st_mode & 0o777, 0o700)
        # Initialization writes a reference; keep the host Keychain out of this fixture.
        self.assertIn("export TYPESAFE_API_KEY='keychain://dotfiles/typesafe/TYPESAFE_API_KEY'", self.credential.read_text())
        self.credential.write_text("export TYPESAFE_API_KEY='fixture-preserved'\n")
        again = self.invoke("--init")
        self.assertEqual(again.returncode, 0, again.stderr)
        self.assertEqual(self.credential.read_text(), "export TYPESAFE_API_KEY='fixture-preserved'\n")
        self.assertNotIn("fixture-preserved", again.stdout + again.stderr)

    def test_init_preserves_dangling_symlink(self) -> None:
        self.credential.parent.mkdir(parents=True)
        target = self.root / "absent"
        self.credential.symlink_to(target)
        result = self.invoke("--init")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.credential.is_symlink())
        self.assertFalse(target.exists())

    def test_help_and_invalid_invocations_do_not_load_credentials(self) -> None:
        marker = self.root / "loaded"
        self.write_credential(f"touch '{marker}'\n")
        for args, code in ((["--help"], 0), ([], 2), (["--"], 2), (["--check", "extra"], 2)):
            with self.subTest(args=args):
                result = self.invoke(*args)
                self.assertEqual(result.returncode, code, result.stderr)
                self.assertFalse(marker.exists())

    def test_missing_empty_and_broken_files_block_commands_and_inherited_keys(self) -> None:
        marker = self.root / "ran"
        self.env["TYPESAFE_API_KEY"] = "fixture-inherited"
        for content in (None, "export TYPESAFE_API_KEY=''\n", "export TYPESAFE_API_KEY='fixture-broken\n"):
            with self.subTest(content=content):
                if content is not None:
                    self.write_credential(content)
                result = self.invoke("--", "touch", str(marker))
                self.assertEqual(result.returncode, 1)
                self.assertFalse(marker.exists())
                self.assertNotIn("fixture-inherited", result.stdout + result.stderr)
                self.assertNotIn("fixture-broken", result.stdout + result.stderr)

    def test_only_dedicated_key_is_added_and_command_keeps_cwd_arguments_and_status(self) -> None:
        marker = self.root / "global-loaded"
        self.write_credential(
            "export TYPESAFE_API_KEY='fixture $value with spaces'\n"
            "export TYPESAFE_FIXTURE_UNRELATED='must-stay-in-subshell'\n"
        )
        (self.secrets / "env.sh").write_text(f"touch '{marker}'\n")
        result = self.invoke(
            "--", sys.executable, "-c",
            "import os, sys; from pathlib import Path; "
            "assert os.environ['TYPESAFE_API_KEY'] == 'fixture $value with spaces'; "
            "assert 'TYPESAFE_FIXTURE_UNRELATED' not in os.environ; "
            "assert str(Path.cwd()) == sys.argv[1]; "
            "assert sys.argv[2:] == ['two words', '--flag']; sys.exit(23)",
            str(self.root), "two words", "--flag",
        )
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertEqual(result.stdout + result.stderr, "")
        self.assertFalse(marker.exists())
        self.assertNotIn("TYPESAFE_API_KEY", self.env)

    def test_check_hides_key_file_output_and_shell_trace(self) -> None:
        self.write_credential(
            "set -x\n"
            "export TYPESAFE_API_KEY='fixture-hidden'\n"
            "printf '%s' \"$TYPESAFE_API_KEY\"\n"
            "printf '%s' \"$TYPESAFE_API_KEY\" >&2\n"
        )
        checked = self.invoke("--check", trace=True)
        self.assertEqual(checked.returncode, 0, checked.stderr)
        self.assertIn("configured (value hidden)", checked.stdout)
        self.assertNotIn("fixture-hidden", checked.stdout + checked.stderr)


if __name__ == "__main__":
    unittest.main()
