#!/usr/bin/env python3
"""Remove or reject machine-specific application filesystem bookmarks."""
import argparse
from pathlib import Path
import plistlib
import sys

BOOKMARK_KEYS = frozenset((
    'NSOSPLastRootDirectory',
    'BackgroundImageBookmark',
    'userApplicationsDirectoryBookmark',
    'browserProfileDirectorySandboxURLBookmark',
))


def remove_bookmarks(value):
    changed = False
    if isinstance(value, dict):
        for key in list(value):
            if key in BOOKMARK_KEYS:
                del value[key]
                changed = True
            else:
                changed = remove_bookmarks(value[key]) or changed
    elif isinstance(value, list):
        for item in value:
            changed = remove_bookmarks(item) or changed
    return changed


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('check', 'sanitize'))
    parser.add_argument('paths', type=Path, nargs='+')
    args = parser.parse_args(argv)
    failed = False
    for path in args.paths:
        try:
            original = path.read_bytes()
            prefs = plistlib.loads(original)
            if not isinstance(prefs, dict):
                raise ValueError('invalid preference root')
            changed = remove_bookmarks(prefs)
            if changed and args.action == 'check':
                print('Non-portable filesystem bookmark in preference snapshot.', file=sys.stderr)
                failed = True
            elif changed:
                fmt = plistlib.FMT_BINARY if original.startswith(b'bplist') else plistlib.FMT_XML
                path.write_bytes(plistlib.dumps(prefs, fmt=fmt, sort_keys=False))
        except (OSError, ValueError, plistlib.InvalidFileException, OverflowError):
            print('Unable to process preference snapshot (details hidden).', file=sys.stderr)
            failed = True
    return int(failed)


if __name__ == '__main__':
    sys.exit(main())
