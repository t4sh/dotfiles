"""Filesystem-bookmark privacy contracts using synthetic preference data."""
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts/public-plist-bookmarks.py'


class BookmarkPrivacyTests(unittest.TestCase):
    def invoke(self, action, path):
        return subprocess.run([sys.executable, str(SCRIPT), action, str(path)],
                              capture_output=True, text=True)

    def test_binary_and_xml_bookmarks_are_rejected_then_removed_without_setting_loss(self):
        for fmt in (plistlib.FMT_BINARY, plistlib.FMT_XML):
            with self.subTest(format=fmt), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / 'prefs.plist'
                keep = {'Window Settings': {'One': {'FontSize': 14}, 'Two': {'FontSize': 16}},
                        'defaultBrowser': 'fixture-browser', 'unrelatedData': b'fixture-kept'}
                dirty = plistlib.loads(plistlib.dumps(keep))
                for profile in dirty['Window Settings'].values():
                    profile['BackgroundImageBookmark'] = b'book-fixture-private-volume'
                dirty['NSOSPLastRootDirectory'] = b'book-fixture-private-dialog'
                dirty['userApplicationsDirectoryBookmark'] = b'book-fixture-private-user'
                dirty['browserProfileDirectorySandboxURLBookmark'] = b'book-fixture-private-path'
                original = plistlib.dumps(dirty, fmt=fmt)
                path.write_bytes(original)
                path.chmod(0o600)
                original_mode = path.stat().st_mode & 0o777
                check = self.invoke('check', path)
                self.assertNotEqual(check.returncode, 0)
                self.assertNotIn('fixture-private', check.stdout + check.stderr)
                self.assertEqual(path.read_bytes(), original)
                result = self.invoke('sanitize', path)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(plistlib.loads(path.read_bytes()), keep)
                self.assertEqual(path.read_bytes().startswith(b'bplist'), fmt == plistlib.FMT_BINARY)
                self.assertEqual(path.stat().st_mode & 0o777, original_mode)
                sanitized = path.read_bytes()
                self.assertEqual(self.invoke('sanitize', path).returncode, 0)
                self.assertEqual(path.read_bytes(), sanitized)
                self.assertEqual(self.invoke('check', path).returncode, 0)

    def test_malformed_input_fails_without_overwrite_or_content_output(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'prefs.plist'
            raw = b'fixture-private-invalid-plist'
            path.write_bytes(raw)
            for action in ('check', 'sanitize'):
                result = self.invoke(action, path)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('fixture-private', result.stdout + result.stderr)
                self.assertEqual(path.read_bytes(), raw)


if __name__ == '__main__':
    unittest.main()
