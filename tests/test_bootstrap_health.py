"""Public-owned checkout-safe fixtures; never import live preferences."""
from pathlib import Path
import os
import shutil
import plistlib
import re
import subprocess
import sys
import tempfile
import unittest
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parents[1]

class PublicBootstrap(unittest.TestCase):
    @unittest.skipUnless(sys.platform == 'darwin', 'doctor uses macOS system probes')
    def test_doctor_explains_missing_xcode_tools_without_installing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home, fakebin = root / 'home', root / 'bin'
            home.mkdir()
            fakebin.mkdir()
            calls = root / 'xcode-select.calls'
            probe = fakebin / 'xcode-select'
            probe.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$XCODE_SELECT_CALLS"\nexit 1\n')
            probe.chmod(0o755)
            (fakebin / 'sleep').write_text('#!/bin/sh\nexit 0\n')
            (fakebin / 'sleep').chmod(0o755)
            result = subprocess.run(
                ['bash', str(ROOT / 'scripts/doctor.sh')],
                env=dict(os.environ, HOME=str(home), DOTFILES=str(ROOT),
                         XCODE_SELECT_CALLS=str(calls), PATH=str(fakebin) + os.pathsep + '/usr/bin:/bin'),
                capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('xcode-select --install', result.stdout)
            self.assertIn('finish the GUI installer', result.stdout)
            self.assertIn('rerun dot doctor', result.stdout)
            self.assertEqual(calls.read_text().splitlines(), ['-p'])

    def test_dock_fallback_matches_its_public_snapshot(self):
        def tiles(path):
            snapshot = plistlib.loads(path.read_bytes())
            result = []
            for tile in snapshot['persistent-apps']:
                app = None
                tile_type = tile.get('tile-type', 'file-tile')
                if tile_type == 'file-tile':
                    url = tile['tile-data']['file-data']['_CFURLString']
                    app = Path(unquote(urlparse(url).path)).stem
                result.append((tile_type, app))
            return result

        layout = ROOT / 'macos/dock-layout.plist'
        backup = ROOT / 'macos/dock-backup.plist'
        self.assertTrue(layout.is_file(), 'the public fallback layout must be checked in')
        fallback, captured = tiles(layout), tiles(backup)
        self.assertEqual([tile for tile in fallback if tile[0] == 'file-tile'],
                         [tile for tile in captured if tile[0] == 'file-tile'])
        self.assertTrue(all(kind in {'file-tile', 'spacer-tile', 'small-spacer-tile'}
                            for kind, _app in fallback))

    @unittest.skipUnless(shutil.which('make'), 'Requires Make for command previews')
    def test_windows_media_targets_dispatch_without_mac_rejection(self):
        for target, flag in (('default-apps', '-OpenSettings'), ('default-apps-check', '-Check')):
            result = subprocess.run(['make', '-n', '-f', 'windows.mk', target], cwd=ROOT,
                                    text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('default-apps ' + flag, result.stdout)

    def test_windows_media_manifest_keeps_supported_extensions_and_source_files(self):
        entries = [line for line in (ROOT / 'config/windows-vlc-associations.tsv').read_text().splitlines()
                   if line and not line.startswith('#') and line != 'extension']
        self.assertEqual(len(entries), 37)
        self.assertEqual(len(set(entries)), len(entries))
        self.assertTrue(all(re.fullmatch(r'\.[a-z0-9]+', entry) for entry in entries))
        self.assertFalse({'.ts', '.ogm', '.ogv', '.iinaplg', '.opus'}.intersection(entries))
        self.assertTrue({'.mp4', '.mkv', '.mp3', '.webm'}.issubset(entries))

    def test_skill_manifest_selectors_and_inventory_are_current(self):
        for script in ('scripts/gen-skillsfile.py', 'agents/compareskills.py'):
            result = subprocess.run([sys.executable, str(ROOT / script), '--check'],
                                    capture_output=True, text=True, cwd=ROOT)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        selectors = [line.split(' --skill ', 1)[1].split(' -g ', 1)[0]
                     for line in (ROOT / 'Skillsfile').read_text().splitlines()
                     if line.startswith('update_skill_source "$NPX" skills add ')]
        self.assertTrue(selectors)
        self.assertTrue(all(',' not in selector for selector in selectors))

    def test_audit_requires_ripgrep(self):
        bash = (str(Path(os.environ.get('ProgramFiles', 'C:/Program Files')) / 'Git/bin/bash.exe')
                if os.name == 'nt' else shutil.which('bash'))
        with tempfile.TemporaryDirectory() as directory:
            # Clear PATH after Bash startup; only shell builtins reach the guard.
            result = subprocess.run(
                [bash, '-c', 'PATH="$1"; export PATH; source "$2"', 'fixture',
                 Path(directory).as_posix(), (ROOT / 'scripts/audit-app-prefs.sh').as_posix()],
                capture_output=True, text=True)
            self.assertEqual(result.returncode, 127, result.stderr)
            self.assertIn('requires ripgrep', result.stderr)
            self.assertNotIn('no issues', result.stdout)

    def test_manifest_snapshots_exist(self):
        manifest_only = {
            'macos/services.plist', 'macos/trackpad.plist',
            'macos/bluetooth-trackpad.plist', 'macos/mouse.plist',
            'macos/bluetooth-mouse.plist',
        }
        for line in (ROOT / 'apps.tsv').read_text().splitlines():
            if line and not line.startswith('#'):
                label, snapshot = line.split('\t')[1:3]
                if snapshot in manifest_only:
                    self.assertFalse((ROOT / snapshot).exists(), label)
                else:
                    self.assertTrue((ROOT / snapshot).is_file(), label)

    @unittest.skipUnless(sys.platform == 'darwin', 'Requires macOS preference tools')
    def test_mac_capture_retains_templates_and_omits_dato(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'checkout'
            root.mkdir()
            for name in ('apps', 'macos', 'services', 'scripts'):
                shutil.copytree(ROOT / name, root / name)
            for name in ('Brewfile', 'apps.tsv', '.node-version'):
                shutil.copy2(ROOT / name, root / name)
            home = Path(directory) / 'profile'
            task_tmp = Path(directory) / 'tmp'
            task_tmp.mkdir()
            dato = home / 'Library/Group Containers/group.com.sindresorhus.Dato/Library/Preferences/group.com.sindresorhus.Dato.plist'
            dato.parent.mkdir(parents=True)
            dato.write_bytes(plistlib.dumps({'sharedTimeZones': ['dummy-personal-zone']}))
            shim = Path(directory) / 'bin'
            shim.mkdir()
            defaults = shim / 'defaults'
            defaults.write_text('#!/bin/sh\ncase "$1:$2" in\n'
                                'export:org.example.fixture) cp "$FIXTURE_EXPORT" "$3";;\n'
                                'export:com.apple.dock) cp "$FIXTURE_DOCK" "$3";;\n'
                                '*) exit 1;;\nesac\n')
            snapshot = root / 'apps/fixture/settings.plist'
            snapshot.parent.mkdir()
            snapshot.write_bytes(plistlib.dumps({'enabled': True, 'order': ['one', 'two'],
                                                 'SULastCheckTime': 'old'}, fmt=plistlib.FMT_BINARY))
            prior = snapshot.read_bytes()
            captured = Path(directory) / 'capture.plist'
            captured.write_bytes(plistlib.dumps({'order': ['one', 'two'], 'enabled': True,
                                                 'SULastCheckTime': 'new'}, sort_keys=False))
            with (root / 'apps.tsv').open('a') as manifest:
                manifest.write('\norg.example.fixture\tFixture\tapps/fixture/settings.plist\n')
            defaults.chmod(0o755)
            brewfile_capture = Path(directory) / 'brewfile-capture'
            shutil.copy2(root / 'Brewfile', brewfile_capture)
            dock_capture = Path(directory) / 'dock-capture.plist'
            shutil.copy2(root / 'macos/dock-backup.plist', dock_capture)
            (root / 'scripts/brewfile.sh').write_text('#!/bin/sh\ncp "$FIXTURE_BREWFILE" "$2"\n')
            gitleaks = shim / 'gitleaks'
            gitleaks.write_text('#!/bin/sh\nexit 0\n')
            gitleaks.chmod(0o755)
            paths = [p for app in ('vscode','cursor','zed','sublime-text') for p in (root / 'apps' / app).rglob('*') if p.is_file()]
            def dock_apps(path):
                snapshot = plistlib.loads(path.read_bytes())
                return [Path(unquote(urlparse(tile['tile-data']['file-data']['_CFURLString']).path)).stem
                        for tile in snapshot['persistent-apps']
                        if tile.get('tile-type', 'file-tile') == 'file-tile']
            before = {p: p.read_bytes() for p in paths}
            env = dict(os.environ, DOTFILES=str(root), HOME=str(home), FIXTURE_EXPORT=str(captured),
                       FIXTURE_BREWFILE=str(brewfile_capture), FIXTURE_DOCK=str(dock_capture),
                       TMPDIR=str(task_tmp),
                       PATH=str(shim) + os.pathsep + os.environ['PATH'])
            subprocess.run(['bash', str(root / 'scripts/backup-apps.sh')], env=env, check=True, capture_output=True)
            self.assertFalse((root / 'apps/dato/dato.plist').exists())
            self.assertEqual(dock_apps(root / 'macos/dock-layout.plist'),
                             dock_apps(root / 'macos/dock-backup.plist'))
            for p, data in before.items():
                self.assertEqual(p.read_bytes(), data, str(p.relative_to(root)))
            self.assertEqual(snapshot.read_bytes(), prior)
            # Repeating the whole backup is stable; changing an ordered setting is not.
            subprocess.run(['bash', str(root / 'scripts/backup-apps.sh')], env=env, check=True, capture_output=True)
            self.assertEqual(snapshot.read_bytes(), prior)
            captured.write_bytes(plistlib.dumps({'enabled': False, 'order': ['two', 'one']}))
            brewfile_capture.write_text(brewfile_capture.read_text() + '\nbrew "fixture-captured"\n')
            fresh_capture = subprocess.run(['bash', str(root / 'scripts/backup-apps.sh')],
                                           env=dict(env, OVERRIDE='1'), check=True,
                                           capture_output=True, text=True)
            self.assertIn('published apps/fixture/settings.plist',
                          fresh_capture.stdout + fresh_capture.stderr)
            self.assertEqual(plistlib.loads(snapshot.read_bytes()), {'enabled': False, 'order': ['two', 'one']})
            self.assertEqual(snapshot.read_bytes(), captured.read_bytes())
            self.assertIn('brew "fixture-captured"', (root / 'Brewfile').read_text())
            # Fail after the publisher installs changed snapshots. Rollback must
            # return all managed roots to their previous bytes and paths.
            def managed_snapshot():
                files = [root / 'Brewfile']
                for name in ('apps', 'macos', 'services'):
                    files.extend(p for p in (root / name).rglob('*') if p.is_file())
                return {str(p.relative_to(root)): (p.read_bytes(), p.stat().st_mode)
                        for p in files}

            retained = managed_snapshot()
            captured.write_bytes(plistlib.dumps({'enabled': True, 'order': ['replacement']}))
            brewfile_capture.write_text(brewfile_capture.read_text() + '\nbrew "fixture-failed"\n')
            failure = Path(directory) / 'publish-failed'
            python = shim / 'python3'
            python.write_text('#!/bin/sh\n'
                              'if [ "${1##*/}" = publish-app-backup.py ] && [ "${2:-}" = publish ] && [ -n "${FIXTURE_FAIL_PUBLISH:-}" ]; then\n'
                              '  "$FIXTURE_PYTHON" "$@" || exit $?\n'
                              '  : > "$FIXTURE_FAIL_PUBLISH"\n'
                              '  exit 73\n'
                              'fi\n'
                              'exec "$FIXTURE_PYTHON" "$@"\n')
            python.chmod(0o755)
            result = subprocess.run(['bash', str(root / 'scripts/backup-apps.sh')],
                                    env=dict(env, OVERRIDE='1', FIXTURE_FAIL_PUBLISH=str(failure),
                                             FIXTURE_PYTHON=sys.executable),
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 73, result.stdout + result.stderr)
            self.assertTrue(failure.exists(), 'The intended publication failure was not reached')
            self.assertIn('published apps/fixture/settings.plist', result.stdout)
            self.assertIn('restoring unchanged published paths', result.stdout)
            self.assertEqual(managed_snapshot(), retained)
            self.assertFalse(list(root.glob('.backup-stage.*')))
            self.assertFalse(list(root.glob('.backup-rollback.*')))

    @unittest.skipUnless(sys.platform == 'darwin', 'Requires macOS plutil')
    def test_public_app_sanitization_and_audit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / '.node-version').write_text((ROOT / '.node-version').read_text())
            fixtures = {
                'clop': {'Paddle-Clop-841006-SD': b'dummy-license', 'ZephyrSyncKey': 'dummy', 'savedPipelines': b'dummy-inventory', 'showMenubarIcon': True},
                'thaw': {'KnownDisplays': b'dummy-display', 'MenuBarItemManager.knownItemIdentifiers': b'dummy-app', 'ShowOnHover': True},
            }
            for app, data in fixtures.items():
                path = root / 'apps' / app / (app + '.plist')
                path.parent.mkdir(parents=True)
                path.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_BINARY))
            env = dict(os.environ, DOTFILES=str(root))
            audit = ['bash', str(ROOT / 'scripts/audit-app-prefs.sh')]
            self.assertNotEqual(subprocess.run(audit, env=env, capture_output=True).returncode, 0)
            subprocess.run(['bash', str(ROOT / 'scripts/sanitize-app-prefs.sh')], env=env, check=True, capture_output=True)
            for app, kept in [('clop', 'showMenubarIcon'), ('thaw', 'ShowOnHover')]:
                self.assertEqual(plistlib.loads((root / 'apps' / app / (app + '.plist')).read_bytes()), {kept: True})
            subprocess.run(audit, env=env, check=True, capture_output=True)
            dato = root / 'apps/dato/dato.plist'
            dato.parent.mkdir(); dato.write_bytes(plistlib.dumps({'sharedTimeZones': []}))
            self.assertNotEqual(subprocess.run(audit, env=env, capture_output=True).returncode, 0)

if __name__ == '__main__':
    unittest.main()
