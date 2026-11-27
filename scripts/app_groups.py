#!/usr/bin/env python3
"""Select app declarations without creating a second package inventory."""
import argparse
import csv
import os
from pathlib import Path
import re
import sys

GROUPS = ('essentials', 'development', 'design', 'ai', 'media', 'browsers',
          'productivity', 'utilities', 'fonts')


def selection(value):
    groups = [part.strip() for part in value.split(',')]
    if not all(groups) or len(groups) != len(set(groups)):
        raise ValueError('App groups must be a nonempty, comma-separated list without duplicates')
    if groups == ['all']:
        return set(GROUPS)
    if groups == ['none']:
        return set()
    if any(group not in GROUPS for group in groups):
        raise ValueError('Unknown app group; choose all, none, or: ' + ', '.join(GROUPS))
    return set(groups) | {'essentials'}


def inventory(root, brewfile=None, manifest=None):
    brewfile = Path(brewfile or root / 'Brewfile')
    manifest = Path(manifest or root / 'config/app-groups.tsv')
    lines = brewfile.read_text().splitlines()
    casks = set()
    for line in lines:
        match = re.match(r'^\s*cask\s+"([^"]+)"', line)
        if match and not match[1].startswith('font-'):
            key = 'cask:' + match[1]
            if key in casks:
                raise ValueError('Duplicate Brewfile app: ' + key)
            casks.add(key)
    mapping = {}
    with manifest.open(newline='') as stream:
        rows = csv.DictReader(stream, delimiter='\t')
        if rows.fieldnames != ['Key', 'Group']:
            raise ValueError('App group manifest must have Key and Group columns')
        for row in rows:
            key, group = row['Key'], row['Group']
            if None in row or not key or group not in GROUPS[:-1]:
                raise ValueError('Invalid app group row: ' + str(key))
            if key in mapping:
                raise ValueError('Duplicate app group key: ' + key)
            mapping[key] = group
    if casks != set(mapping):
        raise ValueError('App group coverage mismatch; missing: ' + ', '.join(sorted(casks - set(mapping)))
                         + '; stale: ' + ', '.join(sorted(set(mapping) - casks)))
    entries = []
    for line in lines:
        match = re.match(r'^\s*(cask|vscode)\s+"([^"]+)"', line)
        if match:
            kind, name = match.groups()
            group = ('development' if kind == 'vscode' else
                     'fonts' if name.startswith('font-') else mapping['cask:' + name])
            entries.append((kind, name, group, line))
    return lines, entries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['list', 'project', 'includes', 'check-project'])
    parser.add_argument('group', nargs='?', choices=GROUPS)
    parser.add_argument('--groups', default=os.environ.get('APP_GROUPS', 'all'))
    parser.add_argument('--brewfile', default=os.environ.get('BREWFILE'))
    parser.add_argument('--manifest', default=os.environ.get('DOTFILES_APP_GROUPS_MANIFEST'))
    args = parser.parse_args()
    root = Path(os.environ.get('DOTFILES', Path(__file__).resolve().parent.parent))
    try:
        chosen = selection(args.groups)
        lines, entries = inventory(root, args.brewfile, args.manifest)
        if args.command == 'list':
            for group in GROUPS:
                count = sum(entry[2] == group for entry in entries)
                print(f'{group:14} {count:3} declarations  ' + ('selected' if group in chosen else 'deferred'))
        elif args.command == 'includes':
            if not args.group:
                parser.error('includes requires a group')
            return 0 if args.group in chosen else 1
        else:
            selected_lines = {entry[3] for entry in entries if entry[2] in chosen}
            for line in lines:
                infrastructure = re.match(r'^\s*(tap\s|cask_args\b)', line)
                baseline = re.match(r'^\s*(brew|uv|npm|mas)\s', line)
                if (line in selected_lines or (infrastructure and chosen)
                        or (args.command == 'check-project' and baseline)):
                    print(line)
    except (OSError, ValueError, csv.Error) as error:
        print('app-groups: ' + str(error), file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main())
