import importlib.util
from pathlib import Path
import plistlib
import sqlite3
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    'capture', Path(__file__).resolve().parents[1] / 'scripts/backup-text-replacements.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class TextReplacementBackupTests(unittest.TestCase):
    def test_live_wal_export_and_failure_preserves_backup(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'source.db'
            output = Path(directory) / 'private/export.plist'
            with sqlite3.connect(source) as db:
                db.execute('PRAGMA journal_mode=WAL')
                db.execute('CREATE TABLE ZTEXTREPLACEMENTENTRY '
                           '(ZSHORTCUT TEXT, ZPHRASE TEXT, ZWASDELETED INTEGER)')
                db.executemany('INSERT INTO ZTEXTREPLACEMENTENTRY VALUES (?, ?, ?)',
                               [('hello', 'Hello 👋', 0), ('old', 'Deleted', 1)])
                db.commit()
                self.assertEqual(module.capture(source, output), 1)
                self.assertEqual(plistlib.loads(output.read_bytes()),
                                 [{'shortcut': 'hello', 'phrase': 'Hello 👋'}])
                self.assertEqual(output.stat().st_mode & 0o777, 0o600)
                before = output.read_bytes()
                db.execute('INSERT INTO ZTEXTREPLACEMENTENTRY VALUES (NULL, NULL, 0)')
                db.commit()
                with self.assertRaises(ValueError):
                    module.capture(source, output)
                self.assertEqual(output.read_bytes(), before)
                db.execute('DELETE FROM ZTEXTREPLACEMENTENTRY')
                db.commit()
                self.assertEqual(module.capture(source, output), 0)
                self.assertEqual(plistlib.loads(output.read_bytes()), [])
            with self.assertRaises(sqlite3.Error):
                module.capture(Path(directory) / 'missing.db', output)
            self.assertFalse((Path(directory) / 'missing.db').exists())


if __name__ == '__main__':
    unittest.main()
