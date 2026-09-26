#!/usr/bin/env python3
"""Read and apply the portable macOS preference policy."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
# Shift, control, option and command are the only modifiers a hot corner accepts.
HOT_CORNER_MODIFIERS = 0x20000 | 0x40000 | 0x80000 | 0x100000
# Documented wvous actions; macOS leaves 8 and 9 unused.
HOT_CORNER_ACTIONS = (0, 1, 2, 3, 4, 5, 6, 7, 10, 11, 12, 13, 14)
# Kinds whose stored integer only ever holds 0 or 1.
BOOLEAN_KINDS = ('bool', 'boolint')
# `defaults write` has no -boolint; the extra kind only tightens validation.
WRITE_FLAGS = {'bool': 'bool', 'boolint': 'int', 'int': 'int'}


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.PIPE).strip()


def schema():
    entries = {}
    for line in (ROOT / 'config/macos-preferences.tsv').read_text().splitlines():
        if not line or line.startswith('#'):
            continue
        domain, key, kind, default = line.split('\t')
        if kind not in WRITE_FLAGS:
            raise ValueError(f'Unsupported preference kind: {kind}')
        entries[domain + '/' + key] = (domain, key, kind, int(default))
    return entries


def destination(value):
    if not isinstance(value, str) or any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise ValueError('Screenshot location must be a plain path')
    expanded = os.path.expanduser(value)
    if not expanded.startswith('/') or Path(expanded) == Path('/'):
        raise ValueError('Screenshot location must be an absolute non-root path')
    return expanded


def fallback_dir():
    """First existing workspace parent from the private, never-projected list."""
    listing = ROOT / 'config/capture-parents.tsv'
    if listing.exists() and not listing.is_symlink():
        for line in listing.read_text().splitlines():
            entry = line.strip()
            if not entry or entry.startswith('#'):
                continue
            parent = Path(os.path.expanduser(entry))
            if parent.is_dir():
                return str(parent / 'Screengrabs')
    return str(Path.home() / 'Desktop/Screengrabs')


def validate(data, entries):
    if not isinstance(data, dict) or set(data) != {'version', 'values', 'screenshot_location'} or data['version'] != 1:
        raise ValueError('Unsupported macOS preference snapshot')
    if not isinstance(data['values'], dict) or set(data['values']) != set(entries):
        raise ValueError('Snapshot keys differ from the supported preference list; retained unchanged')
    for name, value in data['values'].items():
        _, key, kind, _ = entries[name]
        if type(value) is not int or value < 0:
            raise ValueError(f'Invalid integer preference: {name}')
        if kind in BOOLEAN_KINDS and value not in (0, 1):
            raise ValueError(f'Invalid boolean preference: {name}')
        if key.endswith('-corner') and value not in HOT_CORNER_ACTIONS:
            raise ValueError(f'Unsupported hot-corner action: {name}')
        if key.endswith('-modifier') and (value & ~HOT_CORNER_MODIFIERS):
            raise ValueError(f'Unsupported hot-corner modifier: {name}')
    destination(data['screenshot_location'])
    return data


def actual_key(key, major):
    if not key.startswith('@'):
        return key
    # macOS 26 renamed the Control Center visibility prefix.
    return ('NSStatusItem VisibleCC ' if major >= 26 else 'NSStatusItem Visible ') + key[1:]


def default_when_unset(key):
    """Control Center menu-bar visibility is omitted until the operator customizes it."""
    return key.startswith('NSStatusItem Visible')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('expected', 'capture-dir', 'fallback-dir', 'validate', 'apply'))
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    if sys.platform != 'darwin':
        parser.error('This workflow requires macOS')
    entries = schema()
    snapshot = Path(os.environ.get('DOTFILES_MACOS_PREFERENCES', ROOT / 'config/macos-preferences.json'))
    if snapshot.is_symlink():
        raise ValueError('Preference snapshot must not be a symlink')
    saved = validate(json.loads(snapshot.read_text()), entries) if snapshot.exists() else None
    if args.mode == 'validate':
        return
    if args.mode == 'capture-dir':
        print(destination(saved['screenshot_location']) if saved else '')
        return
    if args.mode == 'fallback-dir':
        print(fallback_dir())
        return
    major = int(run('sw_vers', '-productVersion').split('.')[0])
    if args.mode == 'apply' and not saved:
        return
    for name, (domain, key, kind, default) in entries.items():
        value = saved['values'][name] if saved else default
        key = actual_key(key, major)
        if args.mode == 'expected':
            fallback = str(default) if default_when_unset(key) else ''
            print(f'{domain}\t{key}\t{value}\t{fallback}')
        elif args.dry_run:
            print(f'  would apply saved preference: {domain} {key} = {value}')
        else:
            flag = WRITE_FLAGS[kind]
            rendered = ('true' if value else 'false') if kind == 'bool' else str(value)
            try:
                subprocess.run(['defaults', 'write', domain, key, '-' + flag, rendered], check=True)
            except subprocess.CalledProcessError:
                # Match defaults.sh: Accessibility writes need FDA and must not
                # abort the rest of the overlay.
                if domain == 'com.apple.universalaccess':
                    print(f'  ⚠ could not write {domain} {key} '
                          '(Full Disk Access/Accessibility may be required)', file=sys.stderr)
                    continue
                raise ValueError(f'Could not write {domain} {key}') from None


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, EOFError, KeyboardInterrupt, subprocess.CalledProcessError) as error:
        # Never echo captured subprocess output: failed preference reads may contain unrelated data.
        print(f'macOS preference operation failed: {error}', file=sys.stderr)
        sys.exit(1)
