#!/usr/bin/env python3
"""Capture the checked macOS preference subset; never export whole domains."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

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


def gate(payload, note):
    """Run the real backup check against a candidate snapshot, never the saved one."""
    with tempfile.TemporaryDirectory(prefix='macos-preferences-') as temp:
        candidate = Path(temp) / 'candidate.json'
        candidate.write_text(payload)
        checked = subprocess.run(['make', '--no-print-directory', 'macos-check', 'SKIP_FINDER_VIEWS=1'],
                                 cwd=ROOT, env={**os.environ, 'DOTFILES_MACOS_PREFERENCES': str(candidate)})
    if checked.returncode:
        raise ValueError(note)


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


def read_int(domain, key, default):
    try:
        raw = run('defaults', 'read', domain, key)
    except subprocess.CalledProcessError:
        if default_when_unset(key):
            return default
        raise ValueError(f'Could not read {domain} {key}') from None
    try:
        return int(raw)
    except ValueError:
        raise ValueError(f'Invalid integer preference: {domain} {key}') from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('capture', 'expected', 'capture-dir', 'fallback-dir', 'validate', 'apply'))
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--interactive', action='store_true', help='Confirm each changed preference before saving')
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
    if args.mode == 'capture':
        if os.environ.get('DOTFILES_PUBLIC_SNAPSHOT') == '1':
            raise ValueError('Personal macOS preference capture is private-only')
        # 27 provisionally uses the 26+ preference mapping. Fixture-tested;
        # native read-back/restore verification remains pending (macos/KEYBOARD.md).
        if major not in (15, 26, 27):
            raise ValueError('Capture requires a supported macOS major (15, 26, or 27)')
        values = {}
        for name, (domain, key, _, default) in entries.items():
            values[name] = read_int(domain, actual_key(key, major), default)
        try:
            location = destination(run('defaults', 'read', 'com.apple.screencapture', 'location'))
        except subprocess.CalledProcessError:
            raise ValueError('Could not read com.apple.screencapture location') from None
        home = str(Path.home())
        if location.startswith(home + '/'):
            location = '~/' + location[len(home) + 1:]
        data = validate({'version': 1, 'values': values, 'screenshot_location': location}, entries)
        payload = json.dumps(data, indent=2, sort_keys=True) + '\n'
        # Validate the full backup gate against the candidate before publication.
        gate(payload, 'Backup checks still fail with the current preferences adopted. '
                      'Something outside the adoptable set is failing (firewall, stealth mode '
                      'or Touch ID sudo); resolve that, then rerun make backup.')
        old = saved['values'] if saved else {name: row[3] for name, row in entries.items()}
        changes = [(name, old[name], value) for name, value in values.items() if value != old[name]]
        # Consent concerns persisted values; an environment override only affects checks.
        previous = saved['screenshot_location'] if saved else fallback_dir()
        if destination(previous) != destination(location):
            changes.append(('screenshot location', previous, location))
        if args.interactive and not changes:
            raise ValueError('No adoptable preference drift; resolve the failed backup check before retrying')
        if args.interactive and not sys.stdin.isatty():
            raise ValueError('Drift needs terminal confirmation; rerun make backup in a terminal or use OVERRIDE=1')
        for name, previous, current in changes:
            print(f'{name}:\n  Saved:   {previous}\n  Current: {current}')
            if args.interactive:
                while True:
                    answer = input('Accept this change? [y/N]: ').strip().lower()
                    if answer in ('y', 'yes'):
                        break
                    if answer in ('', 'n', 'no'):
                        raise ValueError('Change rejected; backup stopped. No preferences or snapshot changed')
                    print('Enter y to accept or n to reject.')
        # Recheck after the operator answers: live values may have changed during review.
        if args.interactive:
            gate(payload, 'Live settings changed while the review was open; nothing was saved. '
                          'Rerun make backup to review the current values.')
        if args.dry_run:
            print('Preview only; no preferences or snapshot changed.')
            return
        if saved == data:
            print('macOS preference snapshot already matches; unchanged.')
            return
        fd, temporary = tempfile.mkstemp(prefix='.macos-preferences-', dir=snapshot.parent)
        try:
            with os.fdopen(fd, 'w') as stream:
                stream.write(payload)
            # mkstemp is 0600; tracked repo files stay 0644.
            os.chmod(temporary, 0o644)
            os.replace(temporary, snapshot)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
        print('Saved current supported macOS preferences.')
        return
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
