#!/usr/bin/env python3
"""Figma credential isolation and rotation readiness; dummy values only."""

import os
import io
import importlib.util
from contextlib import redirect_stdout, redirect_stderr
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('figma_api', ROOT / 'scripts/check-figma-api.py')
api = importlib.util.module_from_spec(spec)
spec.loader.exec_module(api)


class FigmaEnvTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='figma-env-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.file = self.root / 'config/env/figma.env'
        self.env = {**os.environ, 'DOTFILES_SECRETS_DIR': str(self.root)}
        self.env.pop('FIGMA_TOKEN', None)
        self.env.pop('FIGMA_FIXTURE_OTHER', None)

    def invoke(self, *args):
        return subprocess.run(['bash', '-x', str(ROOT / 'bin/figma-env'), *args],
                              env=self.env, text=True, capture_output=True)

    def test_private_init_preserves_existing_token(self):
        self.assertEqual(self.invoke('--init').returncode, 0)
        self.assertEqual(self.file.stat().st_mode & 0o777, 0o600)
        self.file.write_text("export FIGMA_TOKEN='dummy-current-token'\n")
        self.assertEqual(self.invoke('--init').returncode, 0)
        self.assertIn('dummy-current-token', self.file.read_text())

    def test_only_dedicated_token_is_loaded_and_rotation_takes_effect(self):
        self.invoke('--init')
        (self.root / 'env.sh').write_text('exit 91\n')
        for value in ('dummy-old-token', 'dummy-new-token'):
            self.file.write_text(f"set -x\nexport FIGMA_TOKEN='{value}'\nexport FIGMA_FIXTURE_OTHER='unrelated-secret'\necho source-noise\n")
            result = self.invoke('--', 'bash', '-c',
                                 '[[ "$FIGMA_TOKEN" == "$1" && -z "${FIGMA_FIXTURE_OTHER:-}" ]] || exit 92; exit 17', '_', value)
            self.assertEqual(result.returncode, 17, result.stderr)
            for hidden in (value, 'unrelated-secret', 'source-noise'):
                self.assertNotIn(hidden, result.stdout + result.stderr)

    def test_missing_empty_broken_file_rejects_inherited_token(self):
        self.env['FIGMA_TOKEN'] = 'dummy-inherited-token'
        self.assertNotEqual(self.invoke('--check').returncode, 0)
        self.invoke('--init')
        for content in ('', 'false\n', "export FIGMA_TOKEN='\n"):
            self.file.write_text(content)
            result = self.invoke('--check')
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('dummy-inherited-token', result.stdout + result.stderr)

    def test_api_success_hides_identity_and_uses_header(self):
        response = io.BytesIO(b'{"id":"private-account-id","email":"private@example.test"}')
        response.status = 200
        output = io.StringIO()
        with patch.dict(os.environ, {'FIGMA_TOKEN': 'dummy-token'}, clear=True), \
                patch.object(api.urllib.request, 'build_opener') as opener, \
                redirect_stdout(output), redirect_stderr(output):
            opener.return_value.open.return_value = response
            self.assertEqual(api.main(), 0)
            request = opener.return_value.open.call_args.args[0]
            self.assertEqual(request.get_header('X-figma-token'), 'dummy-token')
            self.assertNotIn('FIGMA_TOKEN', os.environ)
        for hidden in ('dummy-token', 'private-account-id', 'private@example.test'):
            self.assertNotIn(hidden, output.getvalue())

    def test_api_failure_never_prints_exception_or_body(self):
        error = urllib.error.HTTPError('https://api.figma.com/v1/me', 401,
                                      'dummy-token', {}, io.BytesIO(b'private-response'))
        output = io.StringIO()
        with patch.dict(os.environ, {'FIGMA_TOKEN': 'dummy-token'}, clear=True), \
                patch.object(api.urllib.request, 'build_opener') as opener, \
                redirect_stdout(output), redirect_stderr(output):
            opener.return_value.open.side_effect = error
            self.assertEqual(api.main(), 1)
        self.assertIn('HTTP 401', output.getvalue())
        self.assertNotIn('dummy-token', output.getvalue())
        self.assertNotIn('private-response', output.getvalue())


if __name__ == '__main__':
    unittest.main()
