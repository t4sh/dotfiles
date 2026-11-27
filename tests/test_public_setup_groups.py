#!/usr/bin/env python3
"""Public Mac app-group bootstrap regressions using disposable homes and commands."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


def executable(path: Path, body: str) -> None:
    path.write_text("#!/bin/sh\n" + body)
    path.chmod(0o755)


class PublicSetupGroupsTests(unittest.TestCase):
    def bootstrap(self, td: str, groups: str = "all", fail_apps: bool = False):
        home = Path(td) / "home"
        root = home / ".dotfiles"
        scripts = root / "scripts"
        fakebin = Path(td) / "bin"
        scripts.mkdir(parents=True)
        (root / "config").mkdir()
        fakebin.mkdir()
        for source, target in (
            ("install.sh", "install.sh"),
            ("Brewfile", "Brewfile"),
            ("config/app-groups.tsv", "config/app-groups.tsv"),
            ("scripts/app_groups.py", "scripts/app_groups.py"),
        ):
            shutil.copy2(ROOT / source, root / target)
        executable(scripts / "link.sh", "exit 0\n")
        executable(scripts / "restore-apps.sh", 'printf changed > "$HOME/app-settings"\n')
        executable(fakebin / "xcode-select", '[ "$1" = -p ]\n')
        executable(fakebin / "brew", "exit 0\n")
        executable(fakebin / "dscacheutil", 'printf "shell: /bin/zsh\\n"\n')
        make_log = Path(td) / "make.log"
        executable(
            fakebin / "make",
            'printf "%s\\n" "$*" >> "$MAKE_LOG"\n'
            'case "$*" in *" brew-apps") [ "$FAIL_APPS" = 1 ] && exit 9;; esac\n'
            "exit 0\n",
        )
        settings = home / "app-settings"
        settings.write_bytes(b"existing preferences\x00keep\n")
        before = settings.read_bytes()
        env = {
            **os.environ,
            "HOME": str(home),
            "DOTFILES": str(root),
            "PATH": f"{fakebin}:{os.environ['PATH']}",
            "MAKE_LOG": str(make_log),
            "FAIL_APPS": "1" if fail_apps else "0",
            "APP_GROUPS": groups,
        }
        result = subprocess.run(
            ["bash", str(root / "install.sh")],
            input="nnn",
            text=True,
            capture_output=True,
            env=env,
            timeout=20,
        )
        return result, make_log, settings, before

    def test_default_bootstrap_reports_success_and_restores_settings(self):
        with tempfile.TemporaryDirectory() as td:
            result, log, settings, before = self.bootstrap(td)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("Bootstrap stages finished", result.stdout)
            self.assertIn("Selected app phase (all)", result.stdout)
            self.assertIn("make setup-status APP_GROUPS=all", result.stdout)
            self.assertIn("brew-apps", log.read_text())
            self.assertNotEqual(settings.read_bytes(), before)

    def test_partial_bootstrap_preserves_settings_byte_for_byte(self):
        with tempfile.TemporaryDirectory() as td:
            result, log, settings, before = self.bootstrap(td, "essentials")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(settings.read_bytes(), before)
            self.assertIn("Aggregate app preferences preserved", result.stdout)
            self.assertIn("APP_GROUPS=essentials", result.stdout)
            self.assertIn("brew-apps", log.read_text())

    def test_invalid_group_stops_before_declared_installs(self):
        with tempfile.TemporaryDirectory() as td:
            result, log, settings, before = self.bootstrap(td, "unknown")
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(log.exists())
            self.assertEqual(settings.read_bytes(), before)
            self.assertIn("STOPPED  App group selection", result.stdout)

    def test_optional_app_failure_is_incomplete_and_resumable(self):
        with tempfile.TemporaryDirectory() as td:
            result, log, _, _ = self.bootstrap(td, fail_apps=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("optional app phase incomplete", result.stdout)
            self.assertIn("FAILED   Selected apps (all). Retry: make brew-apps", result.stdout)
            self.assertIn("Bootstrap incomplete", result.stdout)
            self.assertIn("hooks", log.read_text())

    def test_real_make_brew_apps_filters_essentials_and_none(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "scripts").mkdir()
            (root / "config").mkdir()
            fakebin = root / "bin"
            fakebin.mkdir()
            for source in ("Makefile", "Brewfile", ".node-version"):
                shutil.copy2(ROOT / source, root / source)
            for source in ("brewfile.sh", "app_groups.py"):
                shutil.copy2(ROOT / "scripts" / source, root / "scripts" / source)
            for source in ("app-groups.tsv", "retired-mas-ids.tsv"):
                shutil.copy2(ROOT / "config" / source, root / "config" / source)
            capture = root / "selected.Brewfile"
            extensions = root / "extensions.log"
            executable(fakebin / "brew", 'cat > "$CAPTURE"\n')
            for editor in ("code", "cursor"):
                executable(fakebin / editor, 'printf "%s\\n" "$*" >> "$EXTENSIONS"\n')
            env = {
                **os.environ,
                "PATH": f"{fakebin}:{os.environ['PATH']}",
                "CAPTURE": str(capture),
                "EXTENSIONS": str(extensions),
            }
            for groups in ("essentials", "none"):
                with self.subTest(groups=groups):
                    capture.unlink(missing_ok=True)
                    result = subprocess.run(
                        ["make", "-f", "Makefile", "brew-apps", f"APP_GROUPS={groups}"],
                        cwd=root,
                        env=env,
                        text=True,
                        capture_output=True,
                        timeout=20,
                    )
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertFalse(extensions.exists())
                    if groups == "essentials":
                        selected = capture.read_text()
                        self.assertIn('cask "google-chrome"', selected)
                        self.assertNotIn('cask "font-', selected)
                        self.assertNotIn('vscode "', selected)
                    else:
                        self.assertIn("APP_GROUPS=none", result.stdout)
                        self.assertFalse(capture.exists() and capture.stat().st_size)


if __name__ == "__main__":
    unittest.main()
