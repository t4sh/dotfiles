"""Public-owned checkout-safe fixtures; never import live preferences."""
from pathlib import Path
import os
import shutil
import plistlib
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class PublicBootstrap(unittest.TestCase):
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
        for line in (ROOT / 'apps.tsv').read_text().splitlines():
            if line and not line.startswith('#'):
                self.assertTrue((ROOT / line.split('\t')[2]).is_file(), line.split('\t')[1])

    def test_mac_capture_retains_templates_and_omits_dato(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'checkout'
            root.mkdir()
            for name in ('apps', 'macos', 'services', 'scripts'):
                shutil.copytree(ROOT / name, root / name)
            for name in ('Brewfile', 'apps.tsv', '.node-version'):
                shutil.copy2(ROOT / name, root / name)
            home = Path(directory) / 'profile'
            dato = home / 'Library/Group Containers/group.com.sindresorhus.Dato/Library/Preferences/group.com.sindresorhus.Dato.plist'
            dato.parent.mkdir(parents=True)
            dato.write_bytes(plistlib.dumps({'sharedTimeZones': ['dummy-personal-zone']}))
            shim = Path(directory) / 'bin'
            shim.mkdir()
            defaults = shim / 'defaults'
            defaults.write_text('#!/bin/sh\nexit 1\n')
            defaults.chmod(0o755)
            (root / 'scripts/brewfile.sh').write_text('#!/bin/sh\ncp "$BREWFILE" "$2"\n')
            paths = [p for app in ('vscode','cursor','zed','sublime-text') for p in (root / 'apps' / app).rglob('*') if p.is_file()]
            paths.append(root / 'macos/dock-backup.plist')
            before = {p: p.read_bytes() for p in paths}
            env = dict(os.environ, DOTFILES=str(root), HOME=str(home), PATH=str(shim) + os.pathsep + os.environ['PATH'])
            subprocess.run(['bash', str(root / 'scripts/backup-apps.sh')], env=env, check=True, capture_output=True)
            self.assertFalse((root / 'apps/dato/dato.plist').exists())
            for p, data in before.items():
                self.assertEqual(p.read_bytes(), data, str(p.relative_to(root)))

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
