#!/usr/bin/env python3
"""Claude Code user-scope MCP wiring and GitHub header helper fixtures (dummy tokens)."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts/claude-mcp-servers.py'
HELPER = ROOT / 'bin/github-mcp-headers'


class ClaudeMcpTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='claude-mcp-fixture-')
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        self.config = self.home / '.claude.json'

    def run_script(self, action):
        return subprocess.run(['python3', str(SCRIPT), action, '--home', str(self.home)],
                              capture_output=True, text=True)

    def fake_gh(self, body):
        gh = self.home / 'gh'
        gh.write_text('#!/bin/bash\n' + body)
        gh.chmod(0o700)
        return {**os.environ, 'GH_BIN': str(gh)}

    def test_setup_adds_servers_preserves_state_and_check_passes(self):
        state = {'numStartups': 3, 'projects': {'/repo': {'mcpServers': {'github': {'command': '/old'}}}},
                 'mcpServers': {'context7': {'type': 'stdio', 'command': '/c7', 'args': []},
                                'paper': {'command': '/stale', 'disabled': True, 'env': {'K': 'fixture-secret'}}}}
        self.config.write_text(json.dumps(state, indent=2) + '\n')
        check = self.run_script('check')
        self.assertEqual(check.returncode, 1)
        self.assertIn('Claude Code github: needs setup', check.stdout)
        setup = self.run_script('setup')
        self.assertEqual(setup.returncode, 0, setup.stderr)
        self.assertNotIn('fixture-secret', setup.stdout + setup.stderr)
        data = json.loads(self.config.read_text())
        servers = data.pop('mcpServers')
        self.assertEqual(servers.pop('context7'), state['mcpServers']['context7'])
        self.assertEqual(servers['paper'], {'disabled': True, 'type': 'stdio',
                                            'command': str(self.home / '.paper/bin/paper'), 'args': ['mcp']})
        self.assertEqual(servers['brilliant'], {'type': 'http', 'url': 'http://127.0.0.1:3333/mcp'})
        self.assertEqual(servers['github']['headersHelper'], str(HELPER))
        self.assertNotIn('headers', servers['github'])
        state.pop('mcpServers')
        self.assertEqual(data, state)
        self.assertEqual(self.config.stat().st_mode & 0o777, 0o600)
        again = self.run_script('check')
        self.assertEqual(again.returncode, 0, again.stdout)
        before = self.config.read_text()
        self.assertEqual(self.run_script('setup').returncode, 0)
        self.assertEqual(self.config.read_text(), before)

    def test_invalid_config_fails_without_rewrite(self):
        self.config.write_text('{"mcpServers": []}\n')
        result = self.run_script('setup')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.config.read_text(), '{"mcpServers": []}\n')

    def test_helper_prints_json_header_and_check_hides_token(self):
        env = self.fake_gh('[[ "$*" == "auth token --hostname github.com" ]] || exit 9\necho fixture-token\n')
        result = subprocess.run([str(HELPER)], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {'Authorization': 'Bearer fixture-token'})
        check = subprocess.run([str(HELPER), '--check'], env=env, capture_output=True, text=True)
        self.assertEqual(check.returncode, 0)
        self.assertNotIn('fixture-token', check.stdout + check.stderr)

    def test_helper_fails_when_gh_has_no_token(self):
        for body in ('exit 1\n', 'echo\n'):
            env = self.fake_gh(body)
            result = subprocess.run(['bash', '-x', str(HELPER)], env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, '')


if __name__ == '__main__':
    unittest.main()
