"""Exercise the generated refresh with dummy installers, never live skills."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = (str(Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "Git/bin/bash.exe")
        if os.name == "nt" else shutil.which("bash"))


class SkillRefreshHoldsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="skill holds ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for folder in ("scripts", "config", "agents/skills"):
            (self.root / folder).mkdir(parents=True)
        for name in ("gen-skillsfile.py", "skill_lock_names.py", "normalize-skill-lock.py"):
            shutil.copy2(ROOT / "scripts" / name, self.root / "scripts" / name)
        skills = {name: {"sourceType": "github", "source": source,
                         "skillFolderHash": "a" * 40, "skillPath": f"{name}/SKILL.md"}
                  for name, source in (("Curated Skill", "fixture/shared"),
                                       ("ordinary", "fixture/shared"),
                                       ("held-only", "fixture/held"))}
        (self.root / "agents/.skill-lock.json").write_text(json.dumps({"skills": skills}), encoding="utf-8")
        self.holds = self.root / "config/skills-refresh-holds.json"
        self.holds.write_text(json.dumps({"Curated Skill": "local 'name' and description",
                                         "held-only": "local launcher"}), encoding="utf-8")
        for name in ("curated-skill", "ordinary", "held-only"):
            folder = self.root / "agents/skills" / name
            folder.mkdir()
            (folder / "SKILL.md").write_bytes(b"local curated content\n")
        installer = self.root / "installer"
        installer.write_text('''#!/usr/bin/env bash
set -eu
printf '%s\\n' "$*" >> "$FIXTURE_ROOT/calls"
# Model the upstream overwrite, including a failure after a partial update.
for name in "$@"; do
  if [ "$name" = ordinary ]; then
    printf 'new upstream content\\n' > "$FIXTURE_ROOT/agents/skills/ordinary/SKILL.md"
  fi
  if [ "$name" = 'Curated Skill' ] || [ "$name" = held-only ]; then
    echo 'curated selector reached installer' >&2
    exit 99
  fi
done
exit "${FIXTURE_EXIT:-0}"
''', encoding="utf-8")
        installer.chmod(0o755)
        self.env = dict(os.environ, NPX=installer.as_posix(), PYTHON_BIN=sys.executable,
                        FIXTURE_ROOT=self.root.as_posix(), PYTHONIOENCODING="utf-8")
        result = self.generate()
        self.assertEqual(result.returncode, 0, result.stderr)

    def generate(self):
        return subprocess.run([sys.executable, str(self.root / "scripts/gen-skillsfile.py")],
                              capture_output=True, text=True, encoding="utf-8", env=self.env)

    def refresh(self):
        command = [BASH, str(self.root / "Skillsfile")]
        if os.name == "nt" and "FIXTURE_COMMANDS" in self.env:
            # Git Bash startup can prepend its own tools to the inherited PATH.
            command = [BASH, "-c",
                       'export PATH="$(cygpath -u "$FIXTURE_COMMANDS"):$PATH"; exec bash "$1"',
                       "fixture", str(self.root / "Skillsfile")]
        return subprocess.run(command, cwd=self.root.parent,
                              env=self.env, capture_output=True, text=True, encoding="utf-8")

    def assert_curated_unchanged(self):
        for name in ("curated-skill", "held-only"):
            self.assertEqual((self.root / "agents/skills" / name / "SKILL.md").read_bytes(),
                             b"local curated content\n")

    def test_repeat_refresh_updates_other_skills_and_preserves_holds(self):
        for _ in range(2):
            result = self.refresh()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("HOLD: fixture/shared / Curated Skill", result.stdout)
            self.assert_curated_unchanged()
        calls = (self.root / "calls").read_text().splitlines()
        self.assertEqual(calls, ["skills add fixture/shared --skill ordinary -g -y --agent codex"] * 2)
        self.assertEqual((self.root / "agents/skills/ordinary/SKILL.md").read_text(),
                         "new upstream content\n")

    def test_failed_installer_never_receives_curated_skills(self):
        self.env["FIXTURE_EXIT"] = "17"
        result = self.refresh()
        self.assertEqual(result.returncode, 17, result.stderr)
        self.assert_curated_unchanged()

    @unittest.skipUnless(os.name == "nt", "real CMD wrapper requires Windows")
    def test_generated_refresh_passes_one_agent_through_real_windows_wrapper(self):
        for name in ("npx-skills-windows.cmd", "summarize-skills-update.py"):
            shutil.copy2(ROOT / "scripts" / name, self.root / "scripts" / name)
        installer = self.root / "fake npx.cmd"
        installer.write_text('@echo off\necho %*>>"%FIXTURE_ROOT%/calls"\nexit /b 0\n', encoding="utf-8")
        self.env.update(NPX=(self.root / "scripts/npx-skills-windows.cmd").as_posix(),
                        NPX_REAL=str(installer))
        result = self.refresh()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = (self.root / "calls").read_text().splitlines()
        self.assertEqual(calls, ["--yes skills add fixture/shared --skill ordinary -g -y --agent codex"])

    def test_timestamp_only_refresh_is_byte_identical_even_on_failure(self):
        lock = self.root / "agents/.skill-lock.json"
        data = json.loads(lock.read_text())
        data["skills"]["ordinary"]["updatedAt"] = "old"
        lock.write_text(json.dumps(data), encoding="utf-8")
        before = lock.read_bytes()
        installer = self.root / "installer"
        installer.write_text('''#!/usr/bin/env bash
"$PYTHON_BIN" - <<'PY'
import json, os
from pathlib import Path
path = Path(os.environ["FIXTURE_ROOT"]) / "agents/.skill-lock.json"
data = json.loads(path.read_text())
data["skills"]["ordinary"]["updatedAt"] = "new"
data["skills"]["Curated Skill"]["updatedAt"] = "new"
data["skills"]["held-only"]["updatedAt"] = "new"
if os.environ.get("FIXTURE_FIELD"):
    data["skills"]["ordinary"][os.environ["FIXTURE_FIELD"]] = "changed"
    data["skills"]["added"] = {"updatedAt": "new"}
    del data["skills"]["removed"]
    data["version"] = 5
path.write_text(json.dumps(data, indent=2) + "\\n")
PY
exit "${FIXTURE_EXIT:-0}"
''', encoding="utf-8")
        for code in ("0", "0", "17"):
            self.env["FIXTURE_EXIT"] = code
            result = self.refresh()
            self.assertEqual(result.returncode, int(code), result.stderr)
            self.assertEqual(lock.read_bytes(), before)
        for field in ("skillFolderHash", "source", "skillPath", "installedAt"):
            with self.subTest(field=field):
                mixed = json.loads(before)
                mixed["skills"]["Curated Skill"]["updatedAt"] = "unchanged"
                mixed["skills"]["removed"] = {}
                lock.write_text(json.dumps(mixed), encoding="utf-8")
                self.assertEqual(self.generate().returncode, 0)
                self.env["FIXTURE_FIELD"] = field
                result = self.refresh()
                self.assertEqual(result.returncode, 17, result.stderr)
                after = json.loads(lock.read_text())
                self.assertEqual(after["skills"]["ordinary"][field], "changed")
                self.assertEqual(after["skills"]["ordinary"]["updatedAt"], "new")
                self.assertIn("added", after["skills"])
                self.assertNotIn("removed", after["skills"])
                self.assertEqual(after["skills"]["Curated Skill"]["updatedAt"], "unchanged")
                self.assertNotIn("updatedAt", after["skills"]["held-only"])
                self.assertEqual(after["version"], 5)

    def test_snapshot_copy_failure_cleans_up_before_install(self):
        temporary = self.root / "temporary"
        temporary.mkdir()
        self.env["TMPDIR"] = temporary.as_posix()
        commands = self.root / "commands"
        commands.mkdir()
        copy = commands / "cp"
        copy.write_text("#!/usr/bin/env bash\nexit 23\n", encoding="utf-8")
        copy.chmod(0o755)
        self.env["FIXTURE_COMMANDS"] = commands.as_posix()
        # POSIX shells retain this order; Windows also prepends after Bash startup.
        self.env["PATH"] = commands.as_posix() + os.pathsep + self.env["PATH"]
        result = self.refresh()
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertFalse((self.root / "calls").exists())
        self.assertEqual(list(temporary.iterdir()), [])

    def test_normalization_failure_preserves_status_and_recovery_snapshot(self):
        lock = self.root / "agents/.skill-lock.json"
        before = lock.read_bytes()
        temporary = self.root / "temporary"
        temporary.mkdir()
        self.env["TMPDIR"] = temporary.as_posix()
        (self.root / "installer").write_text('''#!/usr/bin/env bash
printf 'invalid JSON' > "$FIXTURE_ROOT/agents/.skill-lock.json"
exit "${FIXTURE_EXIT:-0}"
''', encoding="utf-8")
        for code, expected in (("17", 17), ("0", 1)):
            lock.write_bytes(before)
            existing = set(temporary.iterdir())
            self.env["FIXTURE_EXIT"] = code
            result = self.refresh()
            self.assertEqual(result.returncode, expected, result.stderr)
            snapshots = set(temporary.iterdir()) - existing
            self.assertEqual(len(snapshots), 1)
            snapshot = snapshots.pop()
            self.assertEqual(snapshot.read_bytes(), before)
            self.assertIn("pre-refresh lock retained at", result.stderr)

    def test_new_hold_blocks_stale_manifest_before_any_install(self):
        holds = json.loads(self.holds.read_text())
        holds["ordinary"] = "new local edit"
        self.holds.write_text(json.dumps(holds), encoding="utf-8")
        self.assertNotEqual(self.refresh().returncode, 0)
        self.assertFalse((self.root / "calls").exists())
        self.assertEqual(self.generate().returncode, 0)
        self.assertEqual(self.refresh().returncode, 0)
        self.assertFalse((self.root / "calls").exists())

    def test_missing_or_invalid_policy_fails_before_install(self):
        for content in ('{"typo": "unknown skill"}', '{"ordinary": ""}', '[]'):
            self.holds.write_text(content, encoding="utf-8")
            self.assertNotEqual(self.refresh().returncode, 0)
            self.assertFalse((self.root / "calls").exists())
        self.holds.unlink()
        self.assertNotEqual(self.refresh().returncode, 0)
        self.assertFalse((self.root / "calls").exists())

    def test_mac_and_windows_topgrade_cannot_bypass_holds(self):
        # Python 3.9 compatibility: TOML is simple enough to inspect this contract
        # without adding a runtime parser dependency.
        for filename in ("topgrade.toml", "topgrade-windows.toml"):
            config = (ROOT / "config" / filename).read_text(encoding="utf-8")
            disabled = config.split("disable = [", 1)[1].split("]", 1)[0]
            self.assertIn('"skills"', disabled)
        self.assertIn('"Skills" = "make -C ~/.dotfiles skills-update"',
                      (ROOT / "config/topgrade.toml").read_text())


if __name__ == "__main__":
    unittest.main()
