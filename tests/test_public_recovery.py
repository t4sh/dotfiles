"""Public recovery and Finder fixtures: temporary files and mocked preferences only."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load(name, relative):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


vault = load('public_vault', 'scripts/vault-integrity.py')
finder = load('public_finder', 'scripts/apply-finder-views.py')
legacy_finder = load('public_finder_bridge', 'macos/finder-column-settings.py')


class PublicRecoveryTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='public-recovery-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def snapshot(self, name):
        root = self.root / name
        (root / 'payload/secrets').mkdir(parents=True)
        (root / 'payload/secrets/example').write_text('dummy recovery value')
        (root / vault.RECEIPT).write_text(json.dumps({
            'schema': 1, 'entries': vault.inventory(root)}))
        return root

    def test_retention_preserves_baseline_and_refuses_corruption(self):
        baseline = self.snapshot('baselines/20260101-000000')
        for number in range(7):
            self.snapshot(f'20260201-00000{number}')
        command = [sys.executable, str(ROOT / 'scripts/vault-integrity.py'),
                   'prune', str(self.root)]
        oldest = self.root / '20260201-000000/payload/secrets/example'
        oldest.write_text('damaged')
        self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
        self.assertEqual(len(vault.snapshots(self.root)), 7)
        oldest.write_text('dummy recovery value')
        subprocess.run(command, check=True, capture_output=True)
        self.assertEqual(len(vault.verified_snapshots(self.root)), 5)
        self.assertTrue(baseline.is_dir())

    def test_receipt_allows_finder_metadata_but_rejects_changed_payload(self):
        snapshot = self.snapshot('20260201-000000')
        (snapshot / '.DS_Store').write_bytes(b'view state')
        vault.check(snapshot)
        (snapshot / 'payload/secrets/example').write_text('changed')
        with self.assertRaises(ValueError):
            vault.check(snapshot)

    def test_image_sidecars_detect_mutation(self):
        image = self.root / 'DotfilesSecrets.dmg'
        image.write_bytes(b'fake image, never mounted')
        vault.sidecars(image, ['20260201-000000'])
        vault.check_image(image)
        image.write_bytes(b'different fake image')
        with self.assertRaises(ValueError):
            vault.check_image(image)

    def test_restore_rejects_damage_before_touching_target(self):
        snapshot = self.snapshot('20260201-000000')
        target = self.root / 'live-fixture'
        target.mkdir()
        (target / 'keep').write_text('existing dummy value')
        (snapshot / 'payload/secrets/example').unlink()
        result = subprocess.run(
            ['bash', str(ROOT / 'scripts/secrets-restore.sh'), '--apply'],
            env=dict(os.environ, DOTFILES_RESTORE_SOURCE=str(self.root),
                     DOTFILES_SECRETS_DIR=str(target)), capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((target / 'keep').read_text(), 'existing dummy value')

    def test_finder_policy_preserves_unmanaged_options(self):
        original = {'StandardViewOptions': {
            'OtherView': {'keep': 1}, 'ColumnViewOptions': {'ColumnWidth': 300}}}
        changes = finder.preference_changes(original, {})
        options = changes['com.apple.finder']['StandardViewOptions']
        self.assertEqual(options['OtherView'], {'keep': 1})
        self.assertEqual(options['ColumnViewOptions']['ColumnWidth'], 300)
        self.assertEqual(changes['com.apple.finder']['FXArrangeGroupViewBy'], 'Name')
        self.assertEqual(changes['NSGlobalDomain']['NSNavPanelFileListModeForOpenMode2'], 3)
        effective = {**original, **changes['com.apple.finder']}
        self.assertFalse(any(finder.preference_changes(effective, changes['NSGlobalDomain']).values()))

    def test_finder_bridge_delegates_without_live_commands(self):
        with patch.object(legacy_finder.subprocess, 'call', return_value=0) as call:
            with patch.object(sys, 'argv', ['finder', 'apply']):
                self.assertEqual(legacy_finder.main(), 0)
            self.assertEqual(call.call_args.args[0][-1], '--policy-only')

    def test_finder_reset_preserves_protected_and_changed_metadata(self):
        home = self.root.resolve()
        metadata = home / '.DS_Store'
        metadata.write_bytes(b'home layout')
        folder = home / 'example'
        folder.mkdir()
        child = folder / '.DS_Store'
        child.write_bytes(b'old layout')
        with patch.object(finder.Path, 'home', return_value=home):
            self.assertEqual(finder.find_stores([home], [], 1), [child])
            with self.assertRaises(ValueError):
                finder.reset_store(metadata, b'home layout')
            saved = finder.backup_store(child, home / 'backups')
            child.write_bytes(b'new layout')
            with self.assertRaises(RuntimeError):
                finder.reset_store(child, saved)
        self.assertEqual(child.read_bytes(), b'new layout')


if __name__ == '__main__':
    unittest.main()
