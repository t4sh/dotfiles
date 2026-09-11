"""Public preference and refresh fixtures using disposable checkout/profile data."""
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


class PublicPreferences(unittest.TestCase):
    def test_hermes_reactions_roundtrip_preserves_unmanaged_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            live, saved = [Path(directory) / name for name in ('live.json', 'saved.json')]
            live.write_text(json.dumps({'model': {'default': 'fixture/model'},
                                       'display': {'message_reactions': False},
                                       'auth': {'fixture': 'local-only'}}))
            command = [sys.executable, str(ROOT / 'scripts/hermes-settings.py')]
            args = ['--live', str(live), '--snapshot', str(saved)]
            subprocess.run(command + ['capture'] + args, check=True, capture_output=True)
            data = json.loads(saved.read_text())
            self.assertIs(data['display']['message_reactions'], False)
            self.assertNotIn('auth', data)
            changed = json.loads(live.read_text()); changed['display']['message_reactions'] = True
            live.write_text(json.dumps(changed))
            mismatch = subprocess.run(command + ['check'] + args, capture_output=True, text=True)
            self.assertNotEqual(mismatch.returncode, 0)
            self.assertIn('docs/hermes-preferences.md', mismatch.stdout)
            self.assertNotIn('make backup-hermes', mismatch.stdout)
            subprocess.run(command + ['restore'] + args, check=True, capture_output=True)
            result = json.loads(live.read_text())
            self.assertIs(result['display']['message_reactions'], False)
            self.assertEqual(result['auth'], {'fixture': 'local-only'})
            subprocess.run(command + ['check'] + args, check=True, capture_output=True)

    def test_hermes_shared_skills_are_additive_and_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            live, saved = [Path(directory) / name for name in ('live.json', 'saved.json')]
            live.write_text(json.dumps({'skills': {'external_dirs': ['profile-skills']}}))
            saved.write_text(json.dumps({'skills': {'create_dir': '~/.agents/skills', 'external_dirs': ['~/.agents/skills']}}))
            command = [sys.executable, str(ROOT / 'scripts/hermes-settings.py'), 'restore', '--skills-only', '--live', str(live), '--snapshot', str(saved)]
            mismatch = subprocess.run([arg if arg != 'restore' else 'check' for arg in command], capture_output=True, text=True)
            self.assertNotEqual(mismatch.returncode, 0)
            self.assertIn('docs/hermes-preferences.md', mismatch.stdout)
            self.assertNotIn('dot hermes', mismatch.stdout)
            subprocess.run(command, check=True, capture_output=True)
            before = live.read_bytes()
            subprocess.run(command, check=True, capture_output=True)
            self.assertEqual(before, live.read_bytes())
            self.assertEqual(json.loads(before)['skills']['external_dirs'], ['profile-skills', '~/.agents/skills'])

    def test_refresh_refuses_missing_or_stale_policy_before_installer(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for folder in ('scripts', 'agents', 'config'):
                (root / folder).mkdir()
            for file in ('scripts/gen-skillsfile.py', 'scripts/skill_lock_names.py', 'agents/.skill-lock.json', 'Skillsfile'):
                shutil.copyfile(ROOT / file, root / file)
            # Resolution uses installed folder names; a fixture copy avoids real updates.
            shutil.copytree(ROOT / 'agents/skills', root / 'agents/skills')
            policy = root / 'config/skills-refresh-holds.json'
            command = [sys.executable, str(root / 'scripts/gen-skillsfile.py'), '--check']
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
            policy.write_text('{}\n')
            subprocess.run(command, check=True, capture_output=True)
            policy.write_text(json.dumps({'not-a-real-skill': 'fixture'}))
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
            marker = root / 'installer-called'
            fake = root / 'npx'; fake.write_text('#!/bin/sh\ntouch "' + str(marker) + '"\n'); fake.chmod(0o755)
            env = dict(os.environ, NPX=str(fake), PYTHON_BIN=sys.executable)
            self.assertNotEqual(subprocess.run(['bash', str(root / 'Skillsfile')], env=env, capture_output=True).returncode, 0)
            self.assertFalse(marker.exists())

    @unittest.skipUnless(sys.platform == 'darwin', 'macOS preference tools required')
    def test_dock_home_paths_are_portable_without_removing_public_filter(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'macos').mkdir()
            (root / '.node-version').write_text((ROOT / '.node-version').read_text())
            dock = root / 'macos/dock-backup.plist'
            dock.write_bytes(plistlib.dumps({'persistent-apps': [{'tile-data': {'file-data': {'_CFURLString': Path.home().as_uri() + '/Apps/Fixture%20App.app/'}}}], 'persistent-others': []}))
            env = dict(os.environ, DOTFILES=str(root))
            subprocess.run(['bash', str(ROOT / 'scripts/sanitize-app-prefs.sh')], env=env, check=True, capture_output=True)
            data = plistlib.loads(dock.read_bytes())
            self.assertEqual(data['persistent-apps'][0]['tile-data']['file-data']['_CFURLString'], 'file://__HOME__/Apps/Fixture App.app/')
            self.assertNotIn('persistent-others', data)


if __name__ == '__main__':
    unittest.main()
