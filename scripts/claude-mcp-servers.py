#!/usr/bin/env python3
"""Wire Claude Code's user-scope MCP servers that other clients already use, without reading secrets."""

import argparse
import importlib.util
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('context7_clients', ROOT / 'scripts/context7-clients.py')
clients = importlib.util.module_from_spec(spec)
spec.loader.exec_module(clients)


def servers(home):
    # Context7 stays owned by context7-clients.py; these mirror Codex and Zed.
    return [
        ('paper', {'type': 'stdio', 'command': str(home / '.paper/bin/paper'), 'args': ['mcp']}),
        ('brilliant', {'type': 'http', 'url': 'http://127.0.0.1:3333/mcp'}),
        ('github', {'type': 'http', 'url': 'https://api.githubcopilot.com/mcp/',
                    'headersHelper': str(ROOT / 'bin/github-mcp-headers')}),
    ]


def prepare_text(text, name, desired):
    data, _, _ = clients.members(text)
    existing = data.get('mcpServers', {})
    if not isinstance(existing, dict):
        raise ValueError('Expected a server map')
    # Keep only the enable toggle; replace all connection/credential fields.
    prior = existing.get(name, {})
    keep = {key: prior[key] for key in ('disabled', 'enabled') if key in prior}
    return clients.set_member(text, ['mcpServers', name], {**keep, **desired})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('setup', 'check'))
    parser.add_argument('--home', type=Path, default=Path.home())
    args = parser.parse_args()
    path = args.home / '.claude.json'
    try:
        before = path.read_text(encoding='utf-8-sig') if path.exists() else '{}\n'
        after, states = before, []
        for name, desired in servers(args.home):
            updated = prepare_text(after, name, desired)
            states.append((name, updated != after))
            after = updated
        if args.action == 'setup' and after != before:
            current = path.read_text(encoding='utf-8-sig') if path.exists() else '{}\n'
            if current != before:
                raise ValueError('Settings changed during setup; retry')
            clients.write_private(path, after)
        for name, changed in states:
            state = 'configured' if args.action == 'setup' or not changed else 'needs setup'
            print(f'Claude Code {name}: {state}')
        return int(args.action == 'check' and after != before)
    except (OSError, ValueError, TypeError):
        print('claude-mcp-servers: configuration could not be processed; values suppressed', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
