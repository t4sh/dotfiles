#!/usr/bin/env python3
"""Check or sanitize public editor trust/confirmation preferences, never live state."""
import argparse
import json
from pathlib import Path
import re
import sys

TOKENS = r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/'
BOOL_POLICY = {
    'security.workspace.trust.enabled': True,
    'git.allowNoVerifyCommit': False,
    'security.promptForLocalFileProtocolHandling': True,
}


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate setting: ' + key)
        result[key] = value
    return result


def read_jsonc(text):
    cleaned = re.sub(TOKENS, lambda m: m[0] if m[0].startswith('"') else ' ', text)
    cleaned = re.sub(r'"(?:\\.|[^"\\])*"|,\s*(?=[}\]])',
                     lambda m: m[0] if m[0].startswith('"') else '', cleaned)
    data = json.loads(cleaned, object_pairs_hook=unique_object)
    if not isinstance(data, dict):
        raise ValueError('editor settings must be an object')
    return data


def enforce(data, editor):
    issues = []
    if editor == 'zed':
        session = data.get('session', {})
        if not isinstance(session, dict):
            raise ValueError('Zed session settings must be an object')
        if 'trust_all_worktrees' in session and session['trust_all_worktrees'] is not False:
            issues.append('session.trust_all_worktrees must be false')
            session['trust_all_worktrees'] = False
    else:
        for key, safe in BOOL_POLICY.items():
            # Cursor disables workspace trust by default; omission is not sufficient.
            required = editor == 'cursor' and key == 'security.workspace.trust.enabled'
            if (key in data or required) and data.get(key) is not safe:
                issues.append(key + ' must be ' + str(safe).lower())
                data[key] = safe
        key = 'security.workspace.trust.untrustedFiles'
        if key in data and data[key] not in ('prompt', 'newWindow'):
            issues.append(key + ' must prompt or open a restricted new window')
            data[key] = 'prompt'
    return issues


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('check', 'sanitize'))
    parser.add_argument('--editor', required=True, choices=('zed', 'vscode', 'cursor'))
    parser.add_argument('path', type=Path)
    args = parser.parse_args()
    try:
        original = args.path.read_text(encoding='utf-8')
        data = read_jsonc(original)
        issues = enforce(data, args.editor)
        if issues and args.mode == 'sanitize':
            args.path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
        elif issues:
            print('Public editor policy: ' + '; '.join(issues), file=sys.stderr)
            return 1
    except (OSError, ValueError) as error:
        print('Public editor policy: ' + str(error), file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main())
