#!/usr/bin/env python3
"""Confirm Brewfile dump declarations before backup publishes them."""
import argparse
import os
from pathlib import Path
import re
import sys

KINDS = ('tap', 'brew', 'cask', 'mas', 'vscode', 'uv', 'npm')
DECLARATION = re.compile(r'^\s*(tap|brew|cask|mas|vscode|uv|npm)\s+"')


def declaration_key(line):
    match = DECLARATION.match(line)
    if not match:
        return None
    kind = match.group(1)
    if kind == 'mas':
        identity = re.search(r'id:\s*(\d+)', line)
        return (kind, identity.group(1)) if identity else None
    name = re.search(r'"([^"]*)"', line)
    return (kind, name.group(1)) if name else None


def declarations(text):
    items = {}
    for line in text.splitlines():
        key = declaration_key(line)
        if key:
            items[key] = line.rstrip('\n')
    return items


def label(key):
    kind, name = key
    if kind == 'mas':
        return f'mas id:{name}'
    return f'{kind} "{name}"'


def insert_declaration(text, line):
    kind = declaration_key(line)[0]
    rows = text.splitlines(keepends=True)
    last = None
    later = set(KINDS[KINDS.index(kind) + 1:])
    later_index = None
    for index, existing in enumerate(rows):
        key = declaration_key(existing)
        if not key:
            continue
        if key[0] == kind:
            last = index
        elif key[0] in later and later_index is None:
            later_index = index
    addition = line.rstrip('\n') + '\n'
    if last is not None:
        rows.insert(last + 1, addition)
    elif later_index is not None:
        rows.insert(later_index, addition)
    else:
        if rows and not rows[-1].endswith('\n'):
            rows[-1] += '\n'
        rows.append(addition)
    return ''.join(rows)


def replace_declaration(text, key, line):
    rows = text.splitlines(keepends=True)
    replacement = line.rstrip('\n') + '\n'
    for index, existing in enumerate(rows):
        if declaration_key(existing) == key:
            rows[index] = replacement
            return ''.join(rows)
    return insert_declaration(text, line)


def remove_declaration(text, key):
    rows = [row for row in text.splitlines(keepends=True) if declaration_key(row) != key]
    return ''.join(rows)


def changes_between(saved_text, candidate_text):
    saved = declarations(saved_text)
    candidate = declarations(candidate_text)
    changes = []
    for key, line in candidate.items():
        if key not in saved:
            changes.append(('added', key, None, line))
        elif saved[key].strip() != line.strip():
            changes.append(('changed', key, saved[key], line))
    for key, line in saved.items():
        if key not in candidate:
            changes.append(('removed', key, line, None))
    return changes


def confirm(name, previous, current, stdin, stdout):
    stdout.write(f'{name}:\n  Saved:   {previous}\n  Current: {current}\n')
    stdout.flush()
    while True:
        stdout.write('Keep this change? [y/N]: ')
        stdout.flush()
        answer = stdin.readline()
        if answer == '':
            raise EOFError('end of input')
        answer = answer.strip().lower()
        if answer in ('y', 'yes'):
            return True
        if answer in ('', 'n', 'no'):
            return False
        stdout.write('Enter y to keep or n to ignore.\n')


def apply_changes(saved_text, changes, kept):
    result = saved_text
    for action, key, _previous, current in changes:
        if not kept[key]:
            continue
        if action == 'added':
            result = insert_declaration(result, current)
        elif action == 'changed':
            result = replace_declaration(result, key, current)
        else:
            result = remove_declaration(result, key)
    if result and not result.endswith('\n'):
        result += '\n'
    return result


def review(saved_text, candidate_text, *, override=False, interactive=False, stdin=None, stdout=None):
    if saved_text == candidate_text:
        return candidate_text, 0, 0
    changes = changes_between(saved_text, candidate_text)
    if not changes:
        return saved_text, 0, 0
    if override:
        return candidate_text, len(changes), 0
    if not interactive:
        raise ValueError(
            'Brewfile dump needs terminal confirmation; rerun make backup in a terminal or use OVERRIDE=1'
        )
    stdin = stdin or sys.stdin
    stdout = stdout or sys.stdout
    kept = {}
    for _action, key, previous, current in changes:
        kept[key] = confirm(label(key), previous or '<absent>', current or '<absent>', stdin, stdout)
    kept_count = sum(1 for value in kept.values() if value)
    ignored = len(changes) - kept_count
    return apply_changes(saved_text, changes, kept), kept_count, ignored


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--saved', required=True, type=Path)
    parser.add_argument('--candidate', required=True, type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    saved = args.saved.read_text()
    candidate = args.candidate.read_text()
    override = os.environ.get('OVERRIDE', '') == '1'
    result, kept, ignored = review(
        saved,
        candidate,
        override=override,
        interactive=sys.stdin.isatty(),
    )
    destination = args.output or args.candidate
    if result != candidate or destination != args.candidate:
        destination.write_text(result)
    if kept or ignored:
        print(f'Brewfile review: kept {kept}, ignored {ignored}')
    elif result == saved and candidate != saved:
        print('Brewfile dump had no declaration changes; saved file retained')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, EOFError, KeyboardInterrupt) as error:
        print(f'Brewfile review failed: {error}', file=sys.stderr)
        sys.exit(1)
