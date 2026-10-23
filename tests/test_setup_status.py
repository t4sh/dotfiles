#!/usr/bin/env python3
"""Selection boundaries and read-only setup reporting with disposable homes."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from app_groups import GROUPS, inventory, selection
from setup_status import probe


class AppGroupsTests(unittest.TestCase):
    def test_real_inventory_is_exhaustive_and_essentials_are_additive(self):
        _, entries = inventory(ROOT)
        self.assertTrue(entries)
        self.assertEqual(selection('design,ai'), {'essentials', 'design', 'ai'})
        self.assertEqual(selection('all'), set(GROUPS))
        self.assertEqual(selection('none'), set())
        for value in ('', 'all,ai', 'none,ai', 'ai,ai', 'unknown', 'ai,'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                selection(value)

    def test_manifest_errors_fail_before_homebrew_runs(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / 'scripts').mkdir()
            (root / 'config').mkdir()
            for name in ('brewfile.sh', 'app_groups.py'):
                shutil.copy2(ROOT / 'scripts' / name, root / 'scripts' / name)
            (root / 'Brewfile').write_text('cask "one"\n  cask "two"\n')
            (root / 'config/retired-mas-ids.tsv').write_text('# none\n')
            fakebin = root / 'bin'
            fakebin.mkdir()
            log = root / 'brew-called'
            brew = fakebin / 'brew'
            brew.write_text('#!/bin/sh\ntouch "$BREW_LOG"\n')
            brew.chmod(0o755)
            for rows in ('cask:one\tai\n',
                         'cask:one\tai\ncask:two\tai\ncask:old\tai\n',
                         'cask:one\tai\ncask:two\tai\ncask:two\tai\n',
                         'cask:one\tunknown\ncask:two\tai\n'):
                (root / 'config/app-groups.tsv').write_text('Key\tGroup\n' + rows)
                result = subprocess.run(['bash', str(root / 'scripts/brewfile.sh'), 'apps'],
                                        env=dict(os.environ, DOTFILES=str(root), APP_GROUPS='all',
                                                 PATH=str(fakebin) + os.pathsep + os.environ['PATH'],
                                                 BREW_LOG=str(log)), capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertFalse(log.exists())

    def test_group_projection_preserves_options_and_excludes_unselected_apps(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / 'config').mkdir()
            (root / 'Brewfile').write_text(
                'tap "example/tap"\nbrew "git"\ncask "browser"\n'
                '  cask "example/tap/design", trusted: true\ncask "chat"\n'
                'cask "font-one"\nvscode "editor.extension"\n')
            (root / 'config/app-groups.tsv').write_text(
                'Key\tGroup\ncask:browser\tessentials\ncask:example/tap/design\tdesign\ncask:chat\tai\n')
            def project(groups):
                return subprocess.run([sys.executable, str(ROOT / 'scripts/app_groups.py'),
                                       'project', '--groups', groups],
                                      env=dict(os.environ, DOTFILES=str(root)),
                                      check=True, capture_output=True, text=True).stdout
            selected = project('design')
            self.assertIn('cask "browser"', selected)
            self.assertIn('cask "example/tap/design", trusted: true', selected)
            self.assertNotIn('"chat"', selected)
            self.assertNotIn('vscode ', selected)
            self.assertNotIn('font-one', selected)
            self.assertEqual(project('none'), '')
            self.assertIn('vscode "editor.extension"', project('development'))
            self.assertIn('cask "font-one"', project('fonts'))


class SetupStatusTests(unittest.TestCase):
    def test_status_aggregates_failures_and_preserves_settings(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / 'scripts').mkdir()
            (root / 'config').mkdir()
            (root / 'macos').mkdir()
            home = root / 'home'
            (home / '.secrets').mkdir(parents=True)
            prefs = home / 'settings.json'
            prefs.write_text('{"keep":"my settings"}\n')
            (root / 'Brewfile').write_text('cask "browser"\ncask "chat"\n')
            (root / 'config/app-groups.tsv').write_text(
                'Key\tGroup\ncask:browser\tessentials\ncask:chat\tai\n')
            for name in ('setup_status.py', 'app_groups.py'):
                shutil.copy2(ROOT / 'scripts' / name, root / 'scripts' / name)
            for name in ('brewfile.sh', 'link.sh', 'check-services.sh', 'check-hooks.sh', 'audit-apps-drift.sh'):
                code = '1' if name in ('link.sh', 'check-hooks.sh') else '0'
                (root / 'scripts' / name).write_text(f'#!/bin/sh\necho suppressed-private-output\nexit {code}\n')
            (root / 'macos/defaults.sh').write_text('exit 0\n')
            (root / 'scripts/gen-skillsfile.py').write_text('pass\n')
            fakebin = root / 'bin'
            fakebin.mkdir()
            brew = fakebin / 'brew'
            brew.write_text('#!/bin/sh\nprintf "browser\\n"\n')
            brew.chmod(0o755)
            before = prefs.read_bytes()
            result = subprocess.run([sys.executable, '-B', str(root / 'scripts/setup_status.py'), '--groups', 'essentials'],
                                    env=dict(os.environ, HOME=str(home), DOTFILES=str(root),
                                             PATH=str(fakebin) + os.pathsep + os.environ['PATH']),
                                    capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn('PRESENT  essentials', result.stdout)
            self.assertIn('DEFERRED ai', result.stdout)
            self.assertIn('REVIEW   Configuration links', result.stdout)
            self.assertIn('REVIEW   Git hooks', result.stdout)
            self.assertIn('PASS     macOS policy', result.stdout)
            self.assertIn('manual steps are not certified', result.stdout)
            self.assertNotIn('suppressed-private-output', result.stdout + result.stderr)
            self.assertEqual(prefs.read_bytes(), before)
            self.assertFalse(list((root / 'scripts').glob('__pycache__')))

    def test_probe_timeout_is_unknown_not_success(self):
        code, _ = probe([sys.executable, '-c', 'import time; time.sleep(10)'], ROOT, timeout=0.05)
        self.assertIsNone(code)


class BootstrapReportTests(unittest.TestCase):
    def test_terminal_import_reports_progress_then_actual_result(self):
        source = (ROOT / 'install.sh').read_text()
        report = source.split('COMPLETED_STAGES=()', 1)[1].split('prompt_yes_no()', 1)[0]
        terminal = source.split('# Terminal.app profile import quits Terminal.app', 1)[1]
        terminal = '# Terminal.app profile import quits Terminal.app' + terminal
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / 'apps/terminal').mkdir(parents=True)
            (root / 'apps/terminal/terminal.plist').write_text('fixture')
            fakebin = root / 'bin'
            fakebin.mkdir()
            for name, body in {
                'osascript': 'exit 0',
                'defaults': 'echo IMPORT_ATTEMPT; exit "$IMPORT_STATUS"',
            }.items():
                command = fakebin / name
                command.write_text('#!/bin/sh\n' + body + '\n')
                command.chmod(0o755)
            script = root / 'report.sh'
            script.write_text('set -euo pipefail\nBOOTSTRAP_SMOKE=0\nAPP_GROUPS=all\n'
                              'COMPLETED_STAGES=()' + report
                              + 'prompt_yes_no() { REPLY=y; return 0; }\n' + terminal)
            for status in ('0', '9'):
                with self.subTest(import_status=status):
                    result = subprocess.run(['/bin/bash', str(script)],
                                            env=dict(os.environ, DOTFILES=str(root), IMPORT_STATUS=status,
                                                     PATH=str(fakebin) + os.pathsep + os.environ['PATH']),
                                            capture_output=True, text=True, timeout=10)
                    self.assertIn('optional Terminal import is still pending', result.stdout)
                    if status == '0':
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertLess(result.stdout.index('IMPORT_ATTEMPT'),
                                        result.stdout.index('Bootstrap stages finished'))
                        self.assertIn('DONE     Terminal profile import', result.stdout)
                    else:
                        self.assertEqual(result.returncode, 9, result.stderr)
                        self.assertNotIn('Bootstrap stages finished', result.stdout)
                        self.assertIn('Bootstrap incomplete', result.stdout)
                        self.assertIn('STOPPED  Terminal profile import', result.stdout)


if __name__ == '__main__':
    unittest.main()
