#!/usr/bin/env python3
"""Context7 isolation and editor configuration regression fixtures (dummy keys)."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('context7_clients', ROOT / 'scripts/context7-clients.py')
clients = importlib.util.module_from_spec(spec)
spec.loader.exec_module(clients)


class Context7Tests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='context7-fixture-')
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        self.secrets = self.home / 'secrets'
        self.file = self.secrets / 'config/env/context7.env'
        self.file.parent.mkdir(parents=True)
        self.file.write_text("export CONTEXT7_API_KEY='fixture-only-key'\n")
        (self.secrets / 'env.sh').write_text('exit 91\n')
        node = self.home / 'node'
        node.write_text('#!/bin/bash\n[[ "$CONTEXT7_API_KEY" == fixture-only-key && -z "${OTHER_KEY:-}" ]] || exit 92\n[[ "$3" == @upstash/context7-mcp@4.0.3 && "$4" == "argument with spaces" ]] || exit 93\nexit 17\n')
        node.chmod(0o700)
        target = self.home / 'npx-real'
        target.touch()
        npx = self.home / 'npx'
        npx.symlink_to(target)
        self.env = {**os.environ, 'DOTFILES_SECRETS_DIR': str(self.secrets),
                    'NODE_STABLE': str(node), 'NPX_STABLE': str(npx)}
        self.env.pop('OTHER_KEY', None)

    def run_loader(self, *args):
        return subprocess.run(['bash', '-x', str(ROOT / 'bin/context7-mcp'), *args],
                              env=self.env, capture_output=True, text=True)

    def test_dedicated_key_only_and_argument_exit_preservation(self):
        self.file.write_text("set -x\nexport CONTEXT7_API_KEY='fixture-only-key'\nexport OTHER_KEY='other-secret'\necho source-noise\n")
        result = self.run_loader('argument with spaces')
        self.assertEqual(result.returncode, 17, result.stderr)
        for value in ('fixture-only-key', 'other-secret', 'source-noise'):
            self.assertNotIn(value, result.stdout + result.stderr)

    def test_empty_missing_or_broken_file_rejects_inherited_key(self):
        self.env['CONTEXT7_API_KEY'] = 'inherited-secret'
        for content in ('', 'false\n', "export CONTEXT7_API_KEY='\n", None):
            if content is None:
                self.file.unlink()
            else:
                self.file.write_text(content)
            result = self.run_loader('--check')
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('inherited-secret', result.stdout + result.stderr)

    def test_check_validates_runtime_without_launching(self):
        self.assertEqual(self.run_loader('--check').returncode, 0)
        (self.home / 'npx-real').unlink()
        self.assertNotEqual(self.run_loader('--check').returncode, 0)

    def test_merge_is_idempotent_and_preserves_comments_other_servers_and_inputs(self):
        path = self.home / 'settings.json'
        text = '''// user comment
{
  "servers": {
    "other": {"url": "https://example.test", "headers": {"token": "fixture-secret"}},
    "io.github.upstash/context7": {"type":"http", "headers":{"Authorization":"${input:key}"}}, // retain comment
  },
  "inputs": [{"id": "key", "type": "promptString", "password": true}],
  "unrelated": "comma, brace } // not a comment",
}
'''
        path.write_text(text)
        desired = {'type': 'stdio', 'command': '/path with spaces/context7-mcp', 'args': []}
        _, after = clients.prepare(path, 'servers', 'context7', desired)
        before_data = json.loads(clients.clean_jsonc(text))
        after_data = json.loads(clients.clean_jsonc(after))
        self.assertEqual(after_data['servers'].pop('io.github.upstash/context7'), desired)
        before_data['servers'].pop('io.github.upstash/context7')
        self.assertEqual(before_data, after_data)
        self.assertIn('// user comment', after)
        self.assertIn('// retain comment', after)
        path.write_text(after)
        self.assertEqual(clients.prepare(path, 'servers', 'context7', desired), (after, after))

    def test_missing_maps_trailing_comments_and_empty_objects(self):
        for text in ('{}', '{"x": 1 // tail\n}', '{"x": 1, // tail\n}', '{/* comment */}'):
            result = clients.set_member(text, ['mcpServers', 'context7'], {'command': '/wrapper'})
            data = json.loads(clients.clean_jsonc(result))
            self.assertEqual(data['mcpServers']['context7']['command'], '/wrapper')
            self.assertEqual(data.get('x'), json.loads(clients.clean_jsonc(text)).get('x'))

    def test_nested_insert_and_replace_follow_member_depth(self):
        text = ('{\n'
                '  "cursor_animation": {\n'
                '    "enabled": true\n'
                '  },\n'
                '  "context_servers": {\n'
                '    "mcp-server-github": {\n'
                '      "enabled": true\n'
                '    }\n'
                '  },\n'
                '  "theme": "fixture"\n'
                '}\n')
        desired = {'command': '/wrapper', 'args': []}
        inserted = clients.set_member(text, ['context_servers', 'mcp-server-context7'], desired)
        self.assertEqual(inserted, (
            '{\n'
            '  "cursor_animation": {\n'
            '    "enabled": true\n'
            '  },\n'
            '  "context_servers": {\n'
            '    "mcp-server-github": {\n'
            '      "enabled": true\n'
            '    },\n'
            '    "mcp-server-context7": {\n'
            '      "command": "/wrapper",\n'
            '      "args": []\n'
            '    }\n'
            '  },\n'
            '  "theme": "fixture"\n'
            '}\n'))
        replaced = clients.set_member(inserted, ['context_servers', 'mcp-server-context7'],
                                      {'command': '/other', 'args': ['x']})
        self.assertIn('    "mcp-server-context7": {\n'
                      '      "command": "/other",\n'
                      '      "args": [\n'
                      '        "x"\n'
                      '      ]\n'
                      '    }\n'
                      '  },\n', replaced)

    def run_clients(self, action):
        return subprocess.run(['python3', str(ROOT / 'scripts/context7-clients.py'), action,
                               '--home', str(self.home)], capture_output=True, text=True)

    def test_claude_code_user_scope_setup_preserves_state_and_check_passes(self):
        claude = self.home / '.claude.json'
        state = {'numStartups': 3, 'projects': {'/repo': {'mcpServers': {}}},
                 'mcpServers': {'other': {'type': 'stdio', 'command': '/other', 'env': {'K': 'fixture-secret'}}}}
        claude.write_text(json.dumps(state, indent=2) + '\n')
        claude.chmod(0o600)
        check = self.run_clients('check')
        self.assertEqual(check.returncode, 1)
        self.assertIn('Claude Code: needs setup', check.stdout)
        setup = self.run_clients('setup')
        self.assertEqual(setup.returncode, 0, setup.stderr)
        self.assertNotIn('fixture-secret', setup.stdout + setup.stderr)
        data = json.loads(claude.read_text())
        entry = data['mcpServers'].pop('context7')
        self.assertEqual(entry, {'type': 'stdio', 'command': str(ROOT / 'bin/context7-mcp'), 'args': []})
        self.assertEqual(data, state)
        self.assertEqual(claude.stat().st_mode & 0o777, 0o600)
        check = self.run_clients('check')
        self.assertEqual(check.returncode, 0, check.stdout)
        for label in ('Cursor', 'Zed', 'VS Code', 'Claude Code'):
            self.assertIn(f'{label}: configured', check.stdout)

    def test_claude_code_project_scoped_entries_do_not_count_as_user_scope(self):
        claude = self.home / '.claude.json'
        claude.write_text('{"projects": {"/repo": {"mcpServers": {"context7": {"command": "/old"}}}}}\n')
        _, path, group, name, desired = clients.plans(self.home, Path('/launcher'))[-1]
        self.assertEqual((path, group, name), (claude, 'mcpServers', 'context7'))
        _, after = clients.prepare(path, group, name, desired)
        data = json.loads(after)
        self.assertEqual(data['mcpServers']['context7']['command'], '/launcher')
        self.assertEqual(data['projects']['/repo']['mcpServers']['context7']['command'], '/old')

    def test_duplicate_servers_fail_without_rewrite_and_symlinks_survive(self):
        path = self.home / 'config.json'
        original = '{"servers":{"context7":{},"Context7":{}}}'
        path.write_text(original)
        with self.assertRaises(ValueError):
            clients.prepare(path, 'servers', 'context7', {})
        self.assertEqual(path.read_text(), original)
        link = self.home / 'link.json'
        link.symlink_to(path)
        clients.write_private(link, '{}\n')
        self.assertTrue(link.is_symlink())
        self.assertEqual(path.read_text(), '{}\n')
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)


if __name__ == '__main__':
    unittest.main()
