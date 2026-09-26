#!/usr/bin/env python3
"""Export active macOS Text Replacements privately, for System Settings import."""
import os
from pathlib import Path
import plistlib
import sqlite3
import sys
import tempfile


def capture(source, destination):
    # Read the live database (including committed WAL changes) in one query.
    # Do not copy a live SQLite file or export cloud/account metadata.
    with sqlite3.connect(source.resolve().as_uri() + '?mode=ro', uri=True) as db:
        rows = db.execute(
            'SELECT ZSHORTCUT, ZPHRASE FROM ZTEXTREPLACEMENTENTRY '
            'WHERE COALESCE(ZWASDELETED, 0) = 0 ORDER BY ZSHORTCUT, ZPHRASE'
        ).fetchall()
    if any(not isinstance(s, str) or not isinstance(p, str) or not s or not p
           for s, p in rows):
        raise ValueError('Invalid replacement entry; previous backup retained')
    payload = plistlib.dumps([{'shortcut': s, 'phrase': p} for s, p in rows])
    destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(prefix='.text-replacements-', dir=destination.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, destination)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return len(rows)


if __name__ == '__main__':
    if sys.platform != 'darwin':
        sys.exit('Text Replacements backup requires macOS')
    source = Path.home() / 'Library/KeyboardServices/TextReplacements.db'
    destination = Path.home() / '.secrets/apps/text-replacements/Text Substitutions.plist'
    if not source.is_file():
        print('Text Replacements database unavailable; previous backup retained.')
    else:
        os.umask(0o077)
        try:
            count = capture(source, destination)
        except (OSError, sqlite3.Error, ValueError):
            sys.exit('Text Replacements capture failed; previous backup retained. No replacement text logged.')
        print(f'Captured {count} Text Replacements into ~/.secrets/apps/text-replacements/. '
              'Run make secrets-backup to encrypt them.')
