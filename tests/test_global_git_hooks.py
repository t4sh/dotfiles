#!/usr/bin/env python3
"""Exercise additive Git hooks without creating commits or touching user config."""

import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
GIT = os.environ.get("DOTFILES_TEST_GIT", "git")


class GlobalGitHookTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dotfiles-hooks-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base / "repo"
        self.repo.mkdir()
        config = self.base / "gitconfig"
        config.write_text((ROOT / "git/gitconfig-macos").read_text())
        self.env = {
            key: value for key, value in os.environ.items()
            if not key.startswith("GIT_")
        }
        self.env.update(GIT_CONFIG_GLOBAL=str(config), GIT_CONFIG_NOSYSTEM="1")
        self.git("init", "-q")
        # Resolve the installed script location against this checkout, including
        # paths with spaces, without requiring the users symlink to be installed.
        self.git("config", "--file", str(config),
                 "hook.strip-cursor-trailers.command",
                 shlex.quote(str(ROOT / "git/global-hooks/commit-msg")))
        self.modern = "hook.<friendly-name>.event" in self.git("help", "--config").stdout

    def git(self, *args, expected=0):
        result = subprocess.run(
            [GIT, *args], cwd=self.repo, env=self.env,
            text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def hook(self, name, body, directory=".git/hooks"):
        path = self.repo / directory / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("#!/bin/sh\n" + body)
        path.chmod(0o755)

    def message(self, text):
        path = self.repo / "message with spaces.txt"
        path.write_text(text)
        return path

    def require_additive_hooks(self):
        if not self.modern:
            self.skipTest("Git predates additive hooks; repository hooks remain supported")

    def test_existing_pre_commit_still_blocks(self):
        self.hook("pre-commit", "echo blocked >&2\nexit 42\n")
        self.assertIn("blocked", self.git("hook", "run", "pre-commit", expected=42).stderr)

    def test_existing_pre_push_receives_arguments_and_stdin(self):
        self.hook("pre-push", 'printf "%s\\n" "$@" > arguments\ncat > input\nexit 17\n')
        source = self.repo / "refs"
        source.write_text("refs/heads/main abc refs/heads/main def\n")
        self.git("hook", "run", "--to-stdin=" + str(source), "pre-push",
                 "--", "origin", "path with spaces", expected=17)
        self.assertEqual((self.repo / "arguments").read_text(), "origin\npath with spaces\n")
        self.assertEqual((self.repo / "input").read_text(), source.read_text())

    def test_message_filter_and_local_hook_run_once(self):
        self.require_additive_hooks()
        self.hook("commit-msg", 'echo called >> calls\ncat "$1" > observed\n')
        source = (
            "fix: preserve message\n\n"
            "Document why cursoragent@cursor.com is filtered.\n\n"
            "Co-authored-by: Person <person@example.invalid>\n"
            "Co-authored-by: Cursor <cursoragent@cursor.com>\n"
            "Made-with: Cursor\n"
        )
        path = self.message(source)
        self.git("hook", "run", "commit-msg", "--", str(path))
        expected = source.replace("Co-authored-by: Cursor <cursoragent@cursor.com>\n", "")
        expected = expected.replace("Made-with: Cursor\n", "")
        self.assertEqual(path.read_text(), expected)
        self.assertEqual((self.repo / "observed").read_text(), expected)
        self.assertEqual((self.repo / "calls").read_text(), "called\n")

    def test_custom_hook_directory_and_failure_are_preserved(self):
        self.git("config", "core.hooksPath", "custom hooks")
        self.hook("commit-msg", 'echo custom\nexit 23\n', "custom hooks")
        path = self.message("fix: custom hooks\n\nMade-with: Cursor\n")
        result = self.git("hook", "run", "commit-msg", "--", str(path), expected=23)
        self.assertEqual(result.stdout + result.stderr, "custom\n")
        self.assertEqual("Made-with: Cursor" in path.read_text(), not self.modern)

    def test_subject_body_examples_and_other_trailers_are_preserved(self):
        self.require_additive_hooks()
        for source in (
            "fix: handle cursoragent@cursor.com\n",
            "Made-with: Cursor\n",
            "fix: docs\n\nCo-authored-by: Cursor <cursoragent@cursor.com>\n\nExample above is intentional.\n",
            "fix: docs\n\nMade-with: Cursor\nThis is prose, not a trailer block.\n",
            "fix: docs\n\nCo-authored-by: Human <human@example.invalid>\nMade-with: Other\n",
            "fix: docs\n\nMade-with: Cursor\n with a continued value\n",
        ):
            with self.subTest(source=source):
                path = self.message(source)
                self.git("hook", "run", "commit-msg", "--", str(path))
                self.assertEqual(path.read_text(), source)

    def test_interactive_comments_and_case_insensitive_trailers(self):
        self.require_additive_hooks()
        for prefix in ("#", ";"):
            with self.subTest(prefix=prefix):
                self.git("config", "core.commentChar", prefix)
                source = (
                    "fix: interactive\n\n"
                    "co-authored-by: Cursor <cursoragent@cursor.com>\n"
                    "made-with: Cursor\n\n" + prefix + " editor instructions\n"
                )
                path = self.message(source)
                self.git("hook", "run", "commit-msg", "--", str(path))
                self.assertEqual(path.read_text(), "fix: interactive\n\n\n" + prefix + " editor instructions\n")

    def test_local_opt_out_leaves_repository_hook_enabled(self):
        self.require_additive_hooks()
        self.git("config", "hook.strip-cursor-trailers.enabled", "false")
        self.hook("commit-msg", 'echo repository\n')
        source = "fix: opted out\n\nMade-with: Cursor\n"
        path = self.message(source)
        result = self.git("hook", "run", "commit-msg", "--", str(path))
        self.assertEqual(result.stdout + result.stderr, "repository\n")
        self.assertEqual(path.read_text(), source)

    def test_missing_local_hook_is_harmless(self):
        source = "fix: ordinary message\n"
        path = self.message(source)
        self.git("hook", "run", "--ignore-missing", "commit-msg", "--", str(path))
        self.assertEqual(path.read_text(), source)


if __name__ == "__main__":
    unittest.main()
