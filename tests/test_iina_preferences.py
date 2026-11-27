"""Exercise IINA restore with disposable preferences and no personal snapshot."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(sys.platform == 'darwin', 'Requires the macOS policy helper')
class IinaPreferences(unittest.TestCase):
    def test_restore_uses_portable_policy_and_checks_readback(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            root = base / 'checkout'
            scripts = root / 'scripts'
            (scripts / 'lib').mkdir(parents=True)
            (root / 'config').mkdir()
            (root / 'apps/iina').mkdir(parents=True)
            home = base / 'profile'
            home.mkdir()
            for name in ('restore-apps.sh', 'macos-preferences.py'):
                shutil.copy2(ROOT / 'scripts' / name, scripts / name)
            shutil.copy2(ROOT / 'config/macos-preferences.tsv', root / 'config/macos-preferences.tsv')
            (root / 'apps.tsv').write_text('com.colliderli.iina\tIINA\tapps/iina/iina.plist\n')
            (root / 'apps/iina/iina.plist').write_bytes(plistlib.dumps({'volume': 42}))
            (scripts / 'validate-manifests.sh').write_text('#!/bin/sh\nexit 0\n')
            # Avoid all application and signing-key activity, including a real
            # Tower installation on the host. IINA itself remains in scope.
            (scripts / 'lib/running-app-gate.sh').write_text(
                'restore_running_app_gate() { :; }\n'
                'restore_reopen_apps() { :; }\n'
                'restore_app_is_deferred() { [[ "$1" == Tower ]]; }\n')
            shim = base / 'bin'
            shim.mkdir()
            defaults = shim / 'defaults'
            defaults.write_text(f'#!{sys.executable}\n' + '''import json, os, pathlib, plistlib, sys
p = pathlib.Path(os.environ['FIXTURE_STATE'])
args = sys.argv[1:]
if args[:2] == ['import', 'com.colliderli.iina']:
    p.write_text(json.dumps(plistlib.loads(pathlib.Path(args[2]).read_bytes())))
elif args[:4] == ['write', 'com.colliderli.iina', 'screenShotFolder', '-string']:
    state = json.loads(p.read_text())
    state['screenShotFolder'] = args[4]
    p.write_text(json.dumps(state))
elif args == ['read', 'com.colliderli.iina', 'screenShotFolder']:
    print('wrong' if os.environ.get('FIXTURE_BAD_READBACK') else json.loads(p.read_text())['screenShotFolder'])
else:
    raise SystemExit('Unexpected preference access')
''')
            defaults.chmod(0o755)
            state = base / 'state.json'
            snapshot = root / 'config/macos-preferences.json'
            env = dict(os.environ, HOME=str(home), DOTFILES=str(root),
                       DOTFILES_MACOS_PREFERENCES=str(snapshot), FIXTURE_STATE=str(state),
                       PATH=str(shim) + os.pathsep + os.environ['PATH'])
            env.pop('DOTFILES_CAPTURE_DIR', None)

            def restore(overrides=None):
                # Exercise the built-in Bash 3.2 used on a fresh Mac too.
                return subprocess.run(['/bin/bash', str(scripts / 'restore-apps.sh')],
                                      env=dict(env, **(overrides or {})), text=True, capture_output=True)

            result = restore()
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue(state.exists(), result.stdout + result.stderr)
            self.assertEqual(json.loads(state.read_text()),
                             {'volume': 42, 'screenShotFolder': str(home / 'Desktop/Screengrabs')})
            self.assertFalse(snapshot.exists(), 'Restore must not create a personal snapshot')

            # A local saved policy takes precedence over the portable fallback.
            values = {}
            for line in (root / 'config/macos-preferences.tsv').read_text().splitlines():
                if line and not line.startswith('#'):
                    domain, key, kind, default = line.split('\t')
                    values[domain + '/' + key] = int(default)
            saved = str(home / 'Pictures/Saved')
            snapshot.write_text(json.dumps({'version': 1, 'values': values, 'screenshot_location': saved}))
            result = restore()
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(json.loads(state.read_text())['screenShotFolder'], saved)

            override = str(home / 'Pictures/Override')
            result = restore({'DOTFILES_CAPTURE_DIR': override})
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(json.loads(state.read_text())['screenShotFolder'], override)

            before = state.read_bytes()
            for invalid in ('/', 'relative/path'):
                result = restore({'DOTFILES_CAPTURE_DIR': invalid})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('absolute non-root', result.stderr)
                self.assertEqual(state.read_bytes(), before, 'Invalid policy must fail before import')

            result = restore({'FIXTURE_BAD_READBACK': '1'})
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('did not read back', result.stderr)

            # A checkout with no available snapshots still completes cleanly.
            (root / 'apps.tsv').write_text('')
            before = state.read_bytes()
            result = restore()
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('Done. Terminal.app is handled separately:', result.stdout)
            self.assertEqual(state.read_bytes(), before)


if __name__ == '__main__':
    unittest.main()
