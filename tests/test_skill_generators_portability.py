"""Forced-write coverage without raising the shared scripts' Python 3.9 floor."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))


class GeneratorPortabilityTests(unittest.TestCase):
    def test_inventory_is_stable_across_machine_local_skills(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            (repo / "agents/skills").mkdir(parents=True)
            (repo / "scripts").mkdir()
            for relative in ("agents/compareskills.py", "scripts/skill_lock_names.py"):
                shutil.copy2(ROOT / relative, repo / relative)
            (repo / "agents/.skill-lock.json").write_text(json.dumps({
                "version": 4,
                "skills": {
                    name: {"source": "fixture/skills", "sourceType": "github"}
                    for name in ("locked", "gated")
                },
            }), encoding="utf-8")
            (repo / ".gitignore").write_text(
                "agents/skills/gated/\nagents/skills/ignored-local/\n", encoding="utf-8")
            for name in ("locked", "tracked-local"):
                skill = repo / "agents/skills" / name
                skill.mkdir()
                (skill / "SKILL.md").write_text(f"# {name}\n", encoding="utf-8")
            subprocess.run(["git", "init", "-q", str(repo)], check=True)
            subprocess.run(["git", "add", "agents/skills"], cwd=repo, check=True)
            command = [sys.executable, str(repo / "agents/compareskills.py")]

            def generate(*args):
                return subprocess.run(command + list(args), cwd=repo, capture_output=True,
                                      text=True, encoding="utf-8")

            result = generate()
            self.assertEqual(result.returncode, 0, result.stderr)
            readme = repo / "agents/skills/README.md"
            baseline = readme.read_bytes()
            self.assertIn(b"3 managed skills", baseline)
            for name in ("untracked-local", "ignored-local"):
                skill = repo / "agents/skills" / name
                skill.mkdir()
                (skill / "SKILL.md").write_text(f"# {name}\n", encoding="utf-8")
            (repo / "agents/skills/scratch").mkdir()
            for args in ((), ("--check",)):
                result = generate(*args)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("untracked-local", result.stdout)
                self.assertIn("ignored-local", result.stdout)
                self.assertNotIn("scratch", result.stdout)
                self.assertEqual(readme.read_bytes(), baseline)

            # A tracked local skill is required even though it has no lock entry.
            entry = repo / "agents/skills/tracked-local/SKILL.md"
            entry.rename(entry.with_suffix(".saved"))
            result = generate("--check")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("tracked local skills are missing", result.stderr)
            self.assertEqual(readme.read_bytes(), baseline)

            # An archive cannot silently substitute its disk folders for Git ownership.
            (repo / ".git").rename(repo / "git-metadata")
            result = generate()
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("use a Git checkout", result.stderr)
            self.assertEqual(readme.read_bytes(), baseline)

    def test_forced_writes_and_reruns_with_python39_write_text_signature(self):
        original_write = Path.write_text

        def python39_write_text(path, data, encoding=None, errors=None):
            return original_write(path, data, encoding=encoding, errors=errors)

        for relative, output_name in (
            ("scripts/gen-skillsfile.py", "SKILLSFILE"),
            ("agents/compareskills.py", "README_FILE"),
        ):
            with self.subTest(script=relative), tempfile.TemporaryDirectory() as directory:
                spec = importlib.util.spec_from_file_location("generator_fixture", ROOT / relative)
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
                target = Path(directory) / "generated.txt"
                setattr(module, output_name, target)
                with patch.object(Path, "write_text", python39_write_text), patch.object(sys, "argv", [relative]), contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(module.main(), 0)
                    first = target.read_bytes()
                    self.assertTrue(first)
                    self.assertNotIn(b"\r", first)
                    first.decode("utf-8")
                    self.assertEqual(module.main(), 0)
                    self.assertEqual(target.read_bytes(), first)


if __name__ == "__main__":
    unittest.main()
