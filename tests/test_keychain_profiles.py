#!/usr/bin/env python3
"""Readiness checks use fixtures and mocked Keychain metadata queries only."""

import importlib.machinery
import importlib.util
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/check-keychain-profiles.py"
loader = importlib.machinery.SourceFileLoader("check_keychain_profiles", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
checker = importlib.util.module_from_spec(spec)
loader.exec_module(checker)


class KeychainProfileTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.env_dir = Path(self.temp.name) / "env"
        self.env_dir.mkdir()
        self.requirements = Path(self.temp.name) / "required.tsv"
        self.requirements.write_text("")

    def profile(self, name, contents):
        (self.env_dir / (name + ".env")).write_text(contents, encoding="utf-8")

    def run_checker(self, *extra):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = checker.main(["--env-dir", str(self.env_dir), "--requirements", str(self.requirements), *extra])
        return code, out.getvalue(), err.getvalue()

    def test_list_parses_literal_references_and_skips_backup_values(self):
        self.profile("fixture-backup", "# backup\nFIXTURE_PASSWORD='private-backup-value'\n"
                     "export FIXTURE_TOKEN='keychain://dotfiles/fixture/token'\n"
                     "export FIXTURE_HOST='$(touch /unsafe/marker)'\n")
        with patch.object(checker.subprocess, "run") as query:
            code, out, err = self.run_checker("--list")
        self.assertEqual((code, err), (0, ""))
        self.assertEqual(out, "fixture-backup: FIXTURE_TOKEN -> dotfiles/fixture/token\n")
        self.assertNotIn("private-backup-value", out)
        query.assert_not_called()

    def test_metadata_only_queries_present_and_missing_without_output_leak(self):
        self.profile("figma", "FIGMA_TOKEN='keychain://dotfiles/figma/FIGMA_TOKEN'\n")
        self.profile("typesafe", "TYPESAFE_API_KEY=keychain://dotfiles/typesafe/TYPESAFE_API_KEY\n")
        def query(command, **kwargs):
            self.assertEqual(command[:2], ["/usr/bin/security", "find-generic-password"])
            self.assertNotIn("-w", command)
            self.assertNotIn("-g", command)
            self.assertIs(kwargs["stdout"], subprocess.DEVNULL)
            self.assertIs(kwargs["stderr"], subprocess.DEVNULL)
            self.assertEqual(kwargs["timeout"], 5)
            return subprocess.CompletedProcess(command, 0 if "figma" in command[3] else 44,
                                               stdout="secret-output", stderr="secret-error")
        with patch.object(checker.subprocess, "run", side_effect=query) as mocked:
            code, out, err = self.run_checker()
        self.assertEqual(code, 1)
        self.assertEqual(mocked.call_count, 2)
        self.assertIn("FIGMA_TOKEN -> dotfiles/figma/FIGMA_TOKEN: present", out)
        self.assertIn("TYPESAFE_API_KEY -> dotfiles/typesafe/TYPESAFE_API_KEY: missing", out)
        self.assertNotIn("secret-", out + err)

    def test_unavailable_query_is_bounded_and_fails_without_exception_details(self):
        self.profile("figma", "FIGMA_TOKEN=keychain://dotfiles/figma/FIGMA_TOKEN\n")
        with patch.object(checker.subprocess, "run", side_effect=subprocess.TimeoutExpired("secret-output", 5)):
            code, out, err = self.run_checker()
        self.assertEqual(code, 2)
        self.assertIn(": missing", out)
        self.assertIn("unavailable", err)
        self.assertNotIn("secret-output", out + err)

    def test_malformed_reference_and_symlink_fail_closed(self):
        for contents in ("BAD='keychain://service with spaces'\n",
                         "BAD='keychain://$(touch /unsafe/marker)'\n",
                         "BAD=keychain://\n",
                         "-BAD=keychain://service\n",
                         "BAD=keychain://service\nBAD=keychain://service\n",
                         "invalid-key=keychain://service\n"):
            self.profile("broken", contents)
            with patch.object(checker.subprocess, "run") as query:
                code, out, err = self.run_checker()
            self.assertEqual(code, 2)
            self.assertEqual(out, "")
            self.assertIn("invalid", err)
            self.assertNotIn(contents.strip(), err)
            query.assert_not_called()
        (self.env_dir / "broken.env").unlink()
        outside = Path(self.temp.name) / "outside"
        outside.write_text("TOKEN=keychain://service\n")
        (self.env_dir / "escape.env").symlink_to(outside)
        code, out, err = self.run_checker("--list")
        self.assertEqual(code, 2)
        self.assertEqual(out, "")
        self.assertIn("invalid", err)

    def test_duplicate_assignments_fail_before_any_metadata_query(self):
        reference = "FIGMA_TOKEN='keychain://fixture/service'\n"
        for other in ("FIGMA_TOKEN=''\n", "export FIGMA_TOKEN='fixture-literal'\n", reference):
            for contents in (reference + other, other + reference):
                for option in ((), ("--list",)):
                    with self.subTest(contents=contents, option=option):
                        self.profile("figma", contents)
                        with patch.object(checker.subprocess, "run") as query:
                            code, out, err = self.run_checker(*option)
                        self.assertEqual(code, 2)
                        self.assertEqual(out, "")
                        self.assertIn("invalid", err)
                        self.assertNotIn("fixture-", out + err)
                        query.assert_not_called()

    def test_required_profiles_cannot_disappear_behind_empty_inventory(self):
        self.requirements.write_text("figma\tFIGMA_TOKEN\n")
        for content in (None, "OTHER=keychain://unrelated\n", "FIGMA_TOKEN='literal-backup'\n"):
            if content is not None:
                self.profile("figma", content)
            with patch.object(checker.subprocess, "run") as query:
                code, out, err = self.run_checker()
            self.assertEqual(code, 1)
            self.assertIn("required reference missing", out)
            self.assertNotIn("literal-backup", out + err)
            query.assert_not_called()
        self.profile("figma", "FIGMA_TOKEN=keychain://dotfiles/figma/FIGMA_TOKEN\n")
        with patch.object(checker.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)):
            self.assertEqual(self.run_checker()[0], 0)

    def test_missing_dir_and_no_references_have_distinct_results(self):
        self.env_dir.rmdir()
        code, out, err = self.run_checker()
        self.assertEqual(code, 2)
        self.assertEqual(out, "")
        self.assertIn("invalid", err)
        self.env_dir.mkdir()
        self.profile("backup", "PASSWORD='literal-value'\n")
        with patch.object(checker.subprocess, "run") as query:
            code, out, err = self.run_checker()
        self.assertEqual((code, out, err), (0, "keychain profiles: no references\n", ""))
        query.assert_not_called()


if __name__ == "__main__":
    unittest.main()
