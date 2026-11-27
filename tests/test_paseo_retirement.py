#!/usr/bin/env python3
"""Isolated fixtures for the one-time Mac Paseo link retirement."""
from __future__ import annotations

import os
import platform
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "retire-paseo.sh"
NAMES = (
    "paseo",
    "paseo-advisor",
    "paseo-committee",
    "paseo-handoff",
    "paseo-help",
    "paseo-plugin",
)


@unittest.skipUnless(platform.system() == "Darwin", "Mac retirement helper is macOS-only")
class PaseoRetirementTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name).resolve()
        self.repo = self.root / "repo"
        self.home = self.root / "home"
        self.skills = self.home / ".codex" / "skills"
        (self.repo / "scripts").mkdir(parents=True)
        self.skills.mkdir(parents=True)
        shutil.copy2(SCRIPT, self.repo / "scripts" / SCRIPT.name)
        # The retired source tree is intentionally absent, as on current installs.

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def run_helper(self, *args: str) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env["HOME"] = str(self.home)
        return subprocess.run(
            ["bash", str(self.repo / "scripts" / SCRIPT.name), *args],
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

    def add_owned_link(self, name: str) -> Path:
        target = self.skills / name
        source = self.repo / "agents" / "skills" / name
        target.symlink_to(source, target_is_directory=True)
        return target

    def test_preview_then_apply_then_rerun_only_unlinks_exact_owned_links(self) -> None:
        owned = [self.add_owned_link(name) for name in NAMES]
        foreign_source = self.root / "foreign-skill"
        foreign_source.mkdir()
        foreign = self.skills / "paseo-foreign"
        foreign.symlink_to(foreign_source, target_is_directory=True)
        # A legacy-named entry with a different target is foreign and preserved.
        wrong = self.skills / "paseo-help"
        wrong.unlink()
        wrong.symlink_to(foreign_source, target_is_directory=True)
        real_dir = self.skills / "paseo-plugin"
        real_dir.unlink()
        real_dir.mkdir()
        (real_dir / "keep.txt").write_text("keep", encoding="utf-8")
        real_file = self.skills / "paseo-advisor"
        real_file.unlink()
        real_file.write_text("keep", encoding="utf-8")
        owned = [self.skills / n for n in NAMES if n not in {"paseo-help", "paseo-plugin", "paseo-advisor"}]

        preview = self.run_helper()
        self.assertEqual(preview.returncode, 0, preview.stderr)
        self.assertIn("Preview only", preview.stdout)
        self.assertTrue(all(link.is_symlink() for link in owned))
        self.assertEqual((real_dir / "keep.txt").read_text(encoding="utf-8"), "keep")
        self.assertEqual(real_file.read_text(encoding="utf-8"), "keep")
        self.assertEqual(os.readlink(foreign), str(foreign_source))

        applied = self.run_helper("--apply")
        self.assertEqual(applied.returncode, 0, applied.stderr)
        self.assertTrue(
            all(not link.is_symlink() for link in owned),
            f"retained owned entries: {[str(link) for link in owned if link.is_symlink()]}; output={applied.stdout!r}",
        )
        self.assertTrue(wrong.is_symlink())
        self.assertTrue(foreign.is_symlink())
        self.assertEqual((real_dir / "keep.txt").read_text(encoding="utf-8"), "keep")
        self.assertEqual(real_file.read_text(encoding="utf-8"), "keep")

        rerun = self.run_helper("--apply")
        self.assertEqual(rerun.returncode, 0, rerun.stderr)
        self.assertIn("nothing to retire", rerun.stdout)
        self.assertTrue(wrong.is_symlink())

    def test_refuses_symlinked_codex_parent_without_touching_foreign_tree(self) -> None:
        self.skills.rmdir()
        self.skills.parent.rmdir()
        foreign_codex = self.root / "foreign-codex"
        foreign_skills = foreign_codex / "skills"
        foreign_skills.mkdir(parents=True)
        sentinel = foreign_skills / "paseo"
        sentinel.write_text("foreign", encoding="utf-8")
        self.skills.parent.symlink_to(foreign_codex, target_is_directory=True)
        # A symlink at .codex is rejected before the helper can inspect children.
        result = self.run_helper("--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("is a symlink", result.stderr)
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "foreign")

    def test_refuses_symlinked_skills_parent(self) -> None:
        self.skills.rmdir()
        foreign_skills = self.root / "foreign-skills"
        foreign_skills.mkdir()
        sentinel = foreign_skills / "paseo"
        sentinel.write_text("foreign", encoding="utf-8")
        self.skills.symlink_to(foreign_skills, target_is_directory=True)
        result = self.run_helper("--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("is a symlink", result.stderr)
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "foreign")


if __name__ == "__main__":
    unittest.main()
