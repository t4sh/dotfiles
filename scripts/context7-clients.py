#!/usr/bin/env python3
"""Wire the Mac editors and Claude Code to the shared Context7 launcher, without reading secrets."""

import argparse
import json
import os
from pathlib import Path
import re
import sys
import tempfile


def clean_jsonc(text):
    # Replace comments/trailing commas with spaces to retain edit offsets.
    tokens = r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/'
    text = re.sub(tokens, lambda m: m[0] if m[0].startswith('"') else
                  re.sub(r'[^\r\n]', ' ', m[0]), text)
    return re.sub(r'"(?:\\.|[^"\\])*"|,(?=\s*[}\]])',
                  lambda m: m[0] if m[0].startswith('"') else ' ', text)


def members(text):
    """Return root-object value spans; JSON validation precedes every edit."""
    clean = clean_jsonc(text)
    data = json.loads(clean)
    if not isinstance(data, dict):
        raise ValueError("Expected a settings object")
    decoder = json.JSONDecoder()
    pos = clean.index('{') + 1
    spans = {}
    while True:
        while clean[pos].isspace() or clean[pos] == ',':
            pos += 1
        if clean[pos] == '}':
            return data, spans, pos
        key, pos = decoder.raw_decode(clean, pos)
        pos = clean.index(':', pos) + 1
        while clean[pos].isspace():
            pos += 1
        _, end = decoder.raw_decode(clean, pos)
        if key in spans:
            raise ValueError("Duplicate settings key")
        spans[key] = (pos, end)
        pos = end


def line_indent(text, pos):
    start = text.rfind('\n', 0, pos) + 1
    line = text[start:pos]
    return line[:len(line) - len(line.lstrip(' \t'))]


def set_member(text, keys, value):
    data, spans, closing = members(text)
    key = keys[0]
    if len(keys) > 1:
        nested = text[slice(*spans[key])] if key in spans else '{}'
        replacement = set_member(nested, keys[1:], value)
    else:
        if key in data and data[key] == value:
            return text
        replacement = json.dumps(value, indent=2)
    if key in spans:
        start, end = spans[key]
        if len(keys) == 1:
            # Nested substrings keep their file indentation; new leaf values follow
            # the indentation of the line that owns the replaced member.
            replacement = replacement.replace('\n', '\n' + line_indent(text, start))
        return text[:start] + replacement + text[end:]
    # Insert the separator at the last value, before any trailing comment.
    if spans:
        last_end = list(spans.values())[-1][1]
        if ',' not in clean_jsonc(text[last_end:closing]):
            text = text[:last_end] + ',' + text[last_end:]
            closing += 1
    # Indent the new member one level inside this object's closing brace, so a
    # nested insert keeps the file's existing depth.
    close_indent = line_indent(text, closing)
    prefix = text[:closing]
    if text[closing - len(close_indent) - 1:closing - len(close_indent)] == '\n':
        prefix = prefix[:len(prefix) - len(close_indent)]
    else:
        close_indent = ''
        prefix += '\n'
    member_indent = close_indent + '  '
    entry = (member_indent + json.dumps(key) + ': '
             + replacement.replace('\n', '\n' + member_indent) + '\n' + close_indent)
    result = prefix + entry + text[closing:]
    json.loads(clean_jsonc(result))
    return result


def plans(home, launcher):
    command = {"command": str(launcher), "args": []}
    return [
        ("Cursor", home / '.cursor/mcp.json', 'mcpServers', 'context7', command),
        ("Zed", home / '.config/zed/settings.json', 'context_servers',
         'mcp-server-context7', command),
        ("VS Code", home / 'Library/Application Support/Code/User/mcp.json',
         'servers', 'io.github.upstash/context7', {"type": "stdio", **command}),
        # User scope: top-level mcpServers in ~/.claude.json, shared by all projects.
        ("Claude Code", home / '.claude.json', 'mcpServers', 'context7',
         {"type": "stdio", **command}),
    ]


def prepare(path, group, default_name, desired):
    text = path.read_text(encoding='utf-8-sig') if path.exists() else '{}\n'
    data, _, _ = members(text)
    servers = data.get(group, {})
    if not isinstance(servers, dict):
        raise ValueError("Expected a server map")
    matches = [name for name in servers if 'context7' in name.lower()]
    if len(matches) > 1:
        raise ValueError("Multiple Context7 entries; resolve duplicates first")
    name = matches[0] if matches else default_name
    # Preserve editor-specific controls; replace all connection/credential fields.
    prior = servers.get(name, {})
    keep = {key: prior[key] for key in ('disabled', 'enabled', 'autoApprove')
            if key in prior}
    expected = {**keep, **desired}
    return text, set_member(text, [group, name], expected)


def write_private(path, text):
    # Resolve existing symlinks so vault-backed consumer links remain intact.
    path = path.resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.context7-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            stream.write(text)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('setup', 'check'))
    parser.add_argument('--home', type=Path, default=Path.home())
    args = parser.parse_args()
    launcher = Path(__file__).resolve().parents[1] / 'bin/context7-mcp'
    pending = []
    try:
        # Validate every client before changing any file. Never print config values.
        for label, path, group, name, desired in plans(args.home, launcher):
            before, after = prepare(path, group, name, desired)
            pending.append((label, path, before, after))
        failed = False
        for label, path, before, after in pending:
            if before != after:
                if args.action == 'setup':
                    current = path.read_text(encoding='utf-8-sig') if path.exists() else '{}\n'
                    if current != before:
                        raise ValueError("Settings changed during setup; retry")
                    write_private(path, after)
                else:
                    failed = True
            state = 'configured' if args.action == 'setup' or before == after else 'needs setup'
            print(f'{label}: {state}')
        return int(failed)
    except (OSError, ValueError, TypeError):
        print('context7-clients: configuration could not be processed; values suppressed', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
