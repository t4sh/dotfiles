"""Public preference and refresh fixtures using disposable checkout/profile data."""
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location("public_hermes_settings", ROOT / "scripts/hermes-settings.py")
helper = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(helper)


class PublicPreferences(unittest.TestCase):
    @unittest.skipUnless(sys.platform == 'darwin', 'macOS preference tools required')
    def test_terminal_velja_bookmarks_fail_audit_and_are_sanitized(self):
        for fmt in (plistlib.FMT_BINARY, plistlib.FMT_XML):
            with self.subTest(format=fmt), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / '.node-version').write_text((ROOT / '.node-version').read_text())
                terminal = root / 'apps/terminal/terminal.plist'
                velja = root / 'apps/velja/velja.plist'
                terminal.parent.mkdir(parents=True)
                velja.parent.mkdir(parents=True)
                terminal.write_bytes(plistlib.dumps({'Window Settings': {
                    'One': {'FontSize': 14, 'BackgroundImageBookmark': b'book-fixture-private'},
                    'Two': {'FontSize': 16, 'BackgroundImageBookmark': b'book-fixture-private'},
                }}, fmt=fmt))
                velja.write_bytes(plistlib.dumps({'defaultBrowser': 'com.apple.Safari',
                    'userApplicationsDirectoryBookmark': b'book-fixture-private',
                    'browserProfileDirectorySandboxURLBookmark': b'book-fixture-private'}, fmt=fmt))
                extra = root / 'apps/fixture/fixture.plist'
                extra.parent.mkdir(parents=True)
                extra.write_bytes(plistlib.dumps({'NSOSPLastRootDirectory': b'book-fixture-private', 'keep': True}, fmt=fmt))
                env = dict(os.environ, DOTFILES=str(root))
                audit = ['bash', str(ROOT / 'scripts/audit-app-prefs.sh')]
                result = subprocess.run(audit, env=env, capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('filesystem bookmark', result.stdout + result.stderr)
                self.assertNotIn('fixture-private', result.stdout + result.stderr)
                sanitize = ['bash', str(ROOT / 'scripts/sanitize-app-prefs.sh')]
                subprocess.run(sanitize, env=env, check=True, capture_output=True)
                self.assertEqual(plistlib.loads(extra.read_bytes()), {'keep': True})
                self.assertEqual(plistlib.loads(terminal.read_bytes()), {'Window Settings': {
                    'One': {'FontSize': 14}, 'Two': {'FontSize': 16}}})
                self.assertEqual(plistlib.loads(velja.read_bytes()), {'defaultBrowser': 'com.apple.Safari'})
                before = [terminal.read_bytes(), velja.read_bytes()]
                subprocess.run(sanitize, env=env, check=True, capture_output=True)
                self.assertEqual(before, [terminal.read_bytes(), velja.read_bytes()])
                subprocess.run(audit, env=env, check=True, capture_output=True)

    @unittest.skipUnless(sys.platform == 'darwin', 'macOS preference tools required')
    def test_betterzip_snapshot_omits_registration_and_archive_password(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'apps/betterzip').mkdir(parents=True)
            (root / '.node-version').write_text((ROOT / '.node-version').read_text())
            saved = root / 'apps/betterzip/betterzip.plist'
            saved.write_bytes(plistlib.dumps({'MIBRegCode': 'fixture-registration-code',
                                              'MIBSavePresets': [{'name': 'Fixture', 'password': 'fixture-password'}],
                                              'MIBShowAdditionalFinderActions': True}))
            env = dict(os.environ, DOTFILES=str(root))
            audit = subprocess.run(['bash', str(ROOT / 'scripts/audit-app-prefs.sh')],
                                   env=env, capture_output=True, text=True)
            self.assertNotEqual(audit.returncode, 0)
            self.assertIn('BetterZip registration or archive password', audit.stdout)
            subprocess.run(['bash', str(ROOT / 'scripts/sanitize-app-prefs.sh')],
                           env=env, check=True, capture_output=True)
            prefs = plistlib.loads(saved.read_bytes())
            self.assertNotIn('MIBRegCode', prefs)
            self.assertNotIn('password', prefs['MIBSavePresets'][0])
            self.assertTrue(prefs['MIBShowAdditionalFinderActions'])
            sanitized_bytes = saved.read_bytes()
            subprocess.run(['bash', str(ROOT / 'scripts/sanitize-app-prefs.sh')],
                           env=env, check=True, capture_output=True)
            self.assertEqual(saved.read_bytes(), sanitized_bytes)
            subprocess.run(['bash', str(ROOT / 'scripts/audit-app-prefs.sh')],
                           env=env, check=True, capture_output=True)

    @unittest.skipUnless(sys.platform == 'darwin', 'macOS preference tools required')
    def test_stabilization_cannot_restore_removed_registration(self):
        with tempfile.TemporaryDirectory() as directory:
            roots = [Path(directory) / name for name in ('stage', 'previous')]
            for root in roots:
                (root / 'apps/betterzip').mkdir(parents=True)
                (root / '.node-version').write_text((ROOT / '.node-version').read_text())
                path = root / 'apps/betterzip/betterzip.plist'
                path.write_bytes(plistlib.dumps({'MIBRegCode': 'fixture-registration',
                                                 'MIBShowAdditionalFinderActions': True}))
                subprocess.run(['bash', str(ROOT / 'scripts/sanitize-app-prefs.sh')],
                               env=dict(os.environ, DOTFILES=str(root)), check=True, capture_output=True)
            subprocess.run([sys.executable, str(ROOT / 'scripts/stabilize-plist-backups.py'),
                            *map(str, roots)], check=True, capture_output=True)
            self.assertEqual(plistlib.loads((roots[0] / 'apps/betterzip/betterzip.plist').read_bytes()),
                             {'MIBShowAdditionalFinderActions': True})

    def test_public_editor_defaults_preserve_trust_and_confirmations(self):
        for editor in ('zed', 'vscode', 'cursor'):
            result = subprocess.run([sys.executable, str(ROOT / 'scripts/public-editor-policy.py'),
                                     'check', '--editor', editor,
                                     str(ROOT / 'apps' / editor / 'settings.json')],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)

    @unittest.skipUnless(sys.platform == 'darwin', 'macOS preference tools required')
    def test_editor_bypasses_are_rejected_and_sanitized_without_home_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / '.node-version').write_text((ROOT / '.node-version').read_text())
            values = {
                'zed': {'session': {'trust_all_worktrees': True}},
                'vscode': {'security.workspace.trust.enabled': False,
                           'security.workspace.trust.untrustedFiles': 'open',
                           'git.allowNoVerifyCommit': True,
                           'security.promptForLocalFileProtocolHandling': False},
                'cursor': {},  # Default-disabled trust requires an explicit override.
            }
            for editor, settings in values.items():
                settings['editor.fontSize'] = 17
                path = root / 'apps' / editor / 'settings.json'
                path.parent.mkdir(parents=True)
                path.write_text('// keep this comment harmless: "trust_all_worktrees": true\n' +
                                json.dumps(settings, indent=2).replace('\n}', ',\n}') + '\n')
            audit = ['bash', str(ROOT / 'scripts/audit-app-prefs.sh')]
            sanitize = ['bash', str(ROOT / 'scripts/sanitize-app-prefs.sh')]
            env = dict(os.environ, DOTFILES=str(root))
            before = subprocess.run(audit, env=env, capture_output=True, text=True)
            self.assertNotEqual(before.returncode, 0)
            self.assertIn('unsafe public editor trust or confirmation policy', before.stdout)
            subprocess.run(sanitize, env=env, check=True, capture_output=True)
            subprocess.run(audit, env=env, check=True, capture_output=True)
            saved = {}
            for editor in values:
                path = root / 'apps' / editor / 'settings.json'
                saved[editor] = path.read_bytes()
                data = json.loads(path.read_text())
                self.assertEqual(data['editor.fontSize'], 17)
                if editor == 'zed':
                    self.assertIs(data['session']['trust_all_worktrees'], False)
                else:
                    self.assertIs(data['security.workspace.trust.enabled'], True)
                if editor == 'vscode':
                    self.assertIs(data['git.allowNoVerifyCommit'], False)
                    self.assertIs(data['security.promptForLocalFileProtocolHandling'], True)
                    self.assertEqual(data['security.workspace.trust.untrustedFiles'], 'prompt')
            subprocess.run(sanitize, env=env, check=True, capture_output=True)
            for editor in values:
                self.assertEqual((root / 'apps' / editor / 'settings.json').read_bytes(), saved[editor])

    @unittest.skipUnless(sys.platform == 'darwin', 'macOS preference tools required')
    def test_zed_runtime_blocks_are_removed_by_structure_not_indentation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / '.node-version').write_text((ROOT / '.node-version').read_text())
            path = root / 'apps/zed/settings.json'
            path.parent.mkdir(parents=True)
            # A nested member at root indentation and a column-zero closing brace,
            # as an earlier Context7 insert wrote them; strings contain braces.
            path.write_text('{\n'
                            '  "cursor_animation": {\n'
                            '    "enabled": true\n'
                            '  },\n'
                            '  "context_servers": {\n'
                            '    "mcp-server-github": {\n'
                            '      "enabled": true\n'
                            '    },\n'
                            '  \n'
                            '  "mcp-server-context7": {\n'
                            '    "command": "fixture",\n'
                            '    "args": ["{", "}"]\n'
                            '  }\n'
                            '},\n'
                            '  "theme": "fixture"\n'
                            '}\n')
            sanitize = ['bash', str(ROOT / 'scripts/sanitize-app-prefs.sh')]
            env = dict(os.environ, DOTFILES=str(root))
            subprocess.run(sanitize, env=env, check=True, capture_output=True)
            text = path.read_text()
            data = json.loads(text)
            self.assertNotIn('context_servers', data)
            self.assertNotIn('mcp-server-context7', text)
            self.assertEqual(data['theme'], 'fixture')
            self.assertIs(data['cursor_animation']['enabled'], True)
            subprocess.run(sanitize, env=env, check=True, capture_output=True)
            self.assertEqual(path.read_text(), text)

    @unittest.skipUnless(sys.platform == 'darwin', 'macOS preference tools required')
    def test_zed_runtime_blocks_ignore_braces_inside_jsonc_comments(self):
        for comment in ('// Example {', '// Example }', '/* Example { */'):
            with self.subTest(comment=comment), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / '.node-version').write_text((ROOT / '.node-version').read_text())
                path = root / 'apps/zed/settings.json'
                path.parent.mkdir(parents=True)
                path.write_text('// Portable Zed preferences.\n'
                                '{\n'
                                '  "agent": {\n'
                                f'    {comment}\n'
                                '    "favorite_models": ["{"]\n'
                                '  },\n'
                                '  "context_servers": {\n'
                                f'    {comment}\n'
                                '    "fixture": {"enabled": true}\n'
                                '  }, // trailing note }\n'
                                '  "theme": "fixture"\n'
                                '}\n')
                sanitize = ['bash', str(ROOT / 'scripts/sanitize-app-prefs.sh')]
                env = dict(os.environ, DOTFILES=str(root))
                subprocess.run(sanitize, env=env, check=True, capture_output=True)
                text = path.read_text()
                self.assertTrue(text.startswith('// Portable Zed preferences.\n'))
                self.assertNotIn('Example', text)
                data = json.loads('\n'.join(line.split('//')[0] for line in text.splitlines()[1:]))
                self.assertNotIn('agent', data)
                self.assertNotIn('context_servers', data)
                self.assertEqual(data['theme'], 'fixture')
                subprocess.run(sanitize, env=env, check=True, capture_output=True)
                self.assertEqual(path.read_text(), text)

    @unittest.skipUnless(sys.platform == 'darwin', 'macOS preference tools required')
    def test_zed_runtime_member_separator_trivia(self):
        cases = {
            "block comment before comma": (
                '{\n  "context_servers": {"x": {}} /* note */,\n'
                '  "theme": "t"\n}\n'
            ),
            "comma on next line": (
                '{\n  "context_servers": {"x": {}}\n  ,\n  "theme": "t"\n}\n'
            ),
            "trailing comma on next line": (
                '{\n  "theme": "t",\n  "context_servers": {"x": {}}\n  ,\n}\n'
            ),
            "line comment before comma": (
                '{\n  "agent": {"a": 1} // c\n  , "theme": "t"\n}\n'
            ),
            "multiline comment after final member": (
                '{\n  "theme": "t",\n  "context_servers": {} /* note\n'
                '     continued */\n}\n'
            ),
            "multiline comment after separator": (
                '{\n  "agent": {}, /* note\n'
                '     continued */\n  "theme": "t"\n}\n'
            ),
        }
        for name, text in cases.items():
            with self.subTest(case=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / '.node-version').write_text((ROOT / '.node-version').read_text())
                path = root / 'apps/zed/settings.json'
                path.parent.mkdir(parents=True)
                path.write_text(text)
                command = ['bash', str(ROOT / 'scripts/sanitize-app-prefs.sh')]
                env = dict(os.environ, DOTFILES=str(root))
                result = subprocess.run(command, env=env, text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                output = path.read_text()
                tokens = r'"(?:\\.|[^"\\])*"|/\*[\s\S]*?\*/|//[^\n]*'
                body = re.sub(tokens, lambda m: m[0] if m[0].startswith('"') else '', output)
                body = re.sub(r',(?=\s*[}\]])', '', body)
                self.assertEqual(json.loads(body), {'theme': 't'})
                if name.startswith('multiline comment'):
                    self.assertIn('/* note\n     continued */', output)
                subprocess.run(command, env=env, check=True, capture_output=True)
                self.assertEqual(path.read_text(), output)

    @unittest.skipUnless(sys.platform == 'darwin', 'macOS preference tools required')
    def test_zed_sanitizer_fails_closed_on_invalid_jsonc(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / '.node-version').write_text((ROOT / '.node-version').read_text())
            path = root / 'apps/zed/settings.json'
            path.parent.mkdir(parents=True)
            broken = '{\n  "context_servers": {\n    "x": {}\n  },\n},\n  "theme": 1\n}\n'
            path.write_text(broken)
            result = subprocess.run(['bash', str(ROOT / 'scripts/sanitize-app-prefs.sh')],
                                    env=dict(os.environ, DOTFILES=str(root)),
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('invalid Zed JSONC', result.stdout + result.stderr)
            self.assertEqual(path.read_text(), broken)

    def test_editor_policy_preserves_safe_jsonc_and_rejects_duplicate_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'settings.json'
            safe = ('// "security.workspace.trust.enabled": false is only a comment\n'
                    '{"security.workspace.trust.enabled": true, '
                    '"security.workspace.trust.untrustedFiles": "newWindow", '
                    '"label": "https://example.invalid/a//b",}\n')
            path.write_text(safe)
            command = [sys.executable, str(ROOT / 'scripts/public-editor-policy.py'),
                       '--editor', 'cursor', str(path)]
            subprocess.run(command[:2] + ['sanitize'] + command[2:], check=True, capture_output=True)
            self.assertEqual(path.read_text(), safe)
            subprocess.run(command[:2] + ['check'] + command[2:], check=True, capture_output=True)
            path.write_text('{"security.workspace.trust.enabled": false, '
                            '"security.workspace.trust.enabled": true}')
            before = path.read_bytes()
            result = subprocess.run(command[:2] + ['sanitize'] + command[2:],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('duplicate setting', result.stderr)
            self.assertEqual(path.read_bytes(), before)

    def test_object_aliases_capture_check_and_restore_roundtrip(self):
        aliases = {"simple": "test/model", "coding": {"model": "test/coder", "provider": "openrouter"},
                   "inherited": {"model": "test/inherited"},
                   "custom": {"model": "test/reasoner", "provider": "custom",
                              "base_url": "https://example.com/v1%20beta", "key_env": "TEST_API_KEY"},
                   "loopback": {"model": "test/loopback", "base_url": "https://[::1]:443/v1"}}
        source = {"model": {"default": "test/default", "provider": "openrouter", "aliases": aliases}}
        self.assertEqual(helper.project(source, skills_only=True), {})
        for preserve in (False, True):
            with self.subTest(preserve=preserve), tempfile.TemporaryDirectory() as directory:
                live, snapshot = Path(directory) / "config.yaml", Path(directory) / "snapshot.json"
                live.write_text(json.dumps(source), encoding="utf-8")
                before = live.read_bytes(), live.stat().st_mtime_ns
                args = [sys.executable, str(ROOT / "scripts/hermes-settings.py"), "capture",
                        "--live", str(live), "--snapshot", str(snapshot)]
                capture = subprocess.run(args, capture_output=True, text=True)
                self.assertEqual(capture.returncode, 0, capture.stdout)
                self.assertEqual(helper.read_config(snapshot), source)
                self.assertEqual((live.read_bytes(), live.stat().st_mtime_ns), before)
                first = snapshot.read_bytes(), snapshot.stat().st_mtime_ns
                subprocess.run(args, check=True, capture_output=True)
                self.assertEqual((snapshot.read_bytes(), snapshot.stat().st_mtime_ns), first)
                for mode in ("audit", "check"):
                    args[2] = mode
                    subprocess.run(args, check=True, capture_output=True)
                original = {"model": {"default": "local/model", "provider": "local", "api_key": "fixture-only"},
                            "terminal": {"cwd": "local"}}
                live.write_text(json.dumps(original), encoding="utf-8")
                args[2] = "restore"
                if preserve:
                    args.append("--preserve-model-selection")
                subprocess.run(args, check=True, capture_output=True)
                restored = helper.read_config(live)
                self.assertEqual(restored["model"]["aliases"], aliases)
                self.assertEqual(restored["model"]["api_key"], "fixture-only")
                self.assertEqual(restored["terminal"], original["terminal"])
                self.assertEqual(restored["model"]["default"], "local/model" if preserve else "test/default")
                self.assertEqual(restored["model"]["provider"], "local" if preserve else "openrouter")
                first = live.read_bytes(), live.stat().st_mtime_ns
                subprocess.run(args, check=True, capture_output=True)
                self.assertEqual((live.read_bytes(), live.stat().st_mtime_ns), first)
                args[2] = "check"
                subprocess.run(args, check=True, capture_output=True)


    def test_unsafe_object_aliases_fail_before_capture_or_restore_writes(self):
        invalid = [{}, {"provider": "custom"}, {"model": None}, {"model": ["test/model"]},
                   {"model": "test/model", "provider": 42},
                   {"model": "test/model", "key_env": "${TEST_API_KEY}"},
                   {"model": "test/model", "key_env": "sk-fixture-only"},
                   {"model": "test/model", "api_key": "fixture-only"},
                   {"model": "test/model", "default_headers": {"Authorization": "fixture-only"}},
                   {"model": "test/model", "unknown": "fixture-only"},
                   {"model": "sk-fixture-only"}, {"model": "/Users/fixture/private"},
                   {"model": "C:/Users/fixture/private"},
                   {"model": "test/model", "base_url": ["https://example.com"]},
                   {"model": "test/model", "base_url": "https://user:fixture-only@example.com/v1"},
                   {"model": "test/model", "base_url": "https://example.com/v1?key=fixture-only"},
                   {"model": "test/model", "base_url": "https://example.com/v1#fixture-only"},
                   {"model": "test/model", "base_url": "file:///fixture-only"},
                   {"model": "test/model", "base_url": "https://[fixture-only]/v1"},
                   {"model": "test/model", "base_url": "https://[::1]extra/v1"},
                   {"model": "test/model", "base_url": "https://[::1]:bad/v1"},
                   {"model": "test/model", "base_url": "https://[::1]:65536/v1"},
                   {"model": "test/model", "base_url": "https://[::1]:４４３/v1"},
                   {"model": "test/model", "base_url": "https://example.com:bad/v1"},
                   {"model": "test/model", "base_url": "https://example.com:65536/v1"},
                   {"model": "test/model", "base_url": "https://example.com:４４３/v1"}]
        invalid.extend({"model": "test/model", "base_url": value} for value in ("https://example.com\n/v1", "https://example.com\t/v1",
                   "https://example.com\\other/v1", "https://@example.com/v1",
                   "https://example.com:443@/v1", "https://example%2ecom/v1",
                   "https://example.com/%zz/v1", "https://example.com/%/v1",
                   "https://example.com/v1?", "https://example.com/v1#"))
        safe = {"model": {"default": "test/default", "aliases": {"simple": "test/model"}}}
        for alias in invalid:
            for mode in ("capture", "restore", "audit"):
                with self.subTest(alias=alias, mode=mode), tempfile.TemporaryDirectory() as directory:
                    live, snapshot = Path(directory) / "config.yaml", Path(directory) / "snapshot.json"
                    unsafe = {"model": {"default": "test/default", "aliases": {"coding": alias}}}
                    live.write_text(json.dumps(unsafe if mode == "capture" else safe), encoding="utf-8")
                    snapshot.write_text(json.dumps(safe if mode == "capture" else unsafe), encoding="utf-8")
                    before = live.read_bytes(), snapshot.read_bytes()
                    args = ["hermes-settings", mode, "--live", str(live), "--snapshot", str(snapshot)]
                    with patch.object(sys, "argv", args), patch("sys.stdout", new_callable=io.StringIO) as output:
                        self.assertEqual(helper.main(), 1)
                        self.assertNotIn("fixture-only", output.getvalue())
                    self.assertEqual((live.read_bytes(), snapshot.read_bytes()), before)


    def test_invalid_model_base_urls_fail_before_capture_or_restore_writes(self):
        invalid = (42, False, "https://example.com\n/v1", "https://example.com\\other/v1", "https://@example.com/v1", "https://example%2ecom/v1", "https://[fixture-only]/v1", "https://[::1]extra/v1",
                   "https://[::1]:bad/v1", "https://[::1]:65536/v1",
                   "https://[::1]:４４３/v1", "https://example.com:bad/v1",
                   "https://example.com:65536/v1", "https://example.com:４４３/v1")
        safe = {"model": {"default": "test/default", "base_url": "https://[::1]:443/v1"}}
        for base_url in invalid:
            for mode in ("capture", "restore", "audit"):
                with self.subTest(base_url=base_url, mode=mode), tempfile.TemporaryDirectory() as directory:
                    live, snapshot = Path(directory) / "config.yaml", Path(directory) / "snapshot.json"
                    unsafe = {"model": {"default": "test/default", "base_url": base_url}}
                    live.write_text(json.dumps(unsafe if mode == "capture" else safe), encoding="utf-8")
                    snapshot.write_text(json.dumps(safe if mode == "capture" else unsafe), encoding="utf-8")
                    before = live.read_bytes(), snapshot.read_bytes()
                    args = ["hermes-settings", mode, "--live", str(live), "--snapshot", str(snapshot)]
                    with patch.object(sys, "argv", args), patch("sys.stdout", new_callable=io.StringIO):
                        self.assertEqual(helper.main(), 1)
                    self.assertEqual((live.read_bytes(), snapshot.read_bytes()), before)


    def test_hermes_seeded_capture_retains_omitted_policy_and_detects_explicit_drift(self):
        with tempfile.TemporaryDirectory() as directory:
            live, saved = [Path(directory) / name for name in ('live.json', 'saved.json')]
            policy = {'model': {'default': 'fixture/model', 'base_url': 'https://example.com/v1',
                                'aliases': {'quick': 'fixture/fast'}},
                      'display': {'message_reactions': False}}
            saved.write_text(json.dumps(policy, indent=2, sort_keys=True) + '\n', encoding='utf-8')
            live.write_text(json.dumps({'model': {'default': 'fixture/model'},
                                        'auth': {'fixture': 'local-only'}}), encoding='utf-8')
            command = [sys.executable, str(ROOT / 'scripts/hermes-settings.py'), 'capture',
                       '--live', str(live), '--snapshot', str(saved)]
            before = saved.read_bytes(), live.read_bytes()
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(saved.read_bytes(), before[0])
            self.assertEqual(live.read_bytes(), before[1])
            for field, value in (('default', 'fixture/changed'), ('base_url', None), ('aliases', {})):
                with self.subTest(field=field):
                    saved.write_bytes(before[0])
                    live.write_text(json.dumps({'model': {'default': 'fixture/model', field: value},
                                                'display': {'message_reactions': True}}), encoding='utf-8')
                    result = subprocess.run(command, capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    captured = json.loads(saved.read_text(encoding='utf-8'))
                    self.assertEqual(captured['model'][field], value)
                    self.assertTrue(captured['display']['message_reactions'])
                    self.assertNotEqual(saved.read_bytes(), before[0])
            saved.write_text(json.dumps({'model': {'default': 'fixture/model',
                                                 'base_url': 'https://user:password@example.com'}}), encoding='utf-8')
            live.write_text(json.dumps({'model': {'default': 'fixture/model'}}), encoding='utf-8')
            unsafe_before = saved.read_bytes(), live.read_bytes()
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertEqual((saved.read_bytes(), live.read_bytes()), unsafe_before)

    def test_hermes_reactions_roundtrip_preserves_unmanaged_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            live, saved = [Path(directory) / name for name in ('live.json', 'saved.json')]
            live.write_text(json.dumps({'model': {'default': 'fixture/model'},
                                       'display': {'message_reactions': False},
                                       'auth': {'fixture': 'local-only'}}))
            command = [sys.executable, str(ROOT / 'scripts/hermes-settings.py')]
            args = ['--live', str(live), '--snapshot', str(saved)]
            subprocess.run(command + ['capture'] + args, check=True, capture_output=True)
            data = json.loads(saved.read_text())
            self.assertIs(data['display']['message_reactions'], False)
            self.assertNotIn('auth', data)
            changed = json.loads(live.read_text()); changed['display']['message_reactions'] = True
            live.write_text(json.dumps(changed))
            mismatch = subprocess.run(command + ['check'] + args, capture_output=True, text=True)
            self.assertNotEqual(mismatch.returncode, 0)
            self.assertIn('docs/hermes-preferences.md', mismatch.stdout)
            self.assertNotIn('make backup-hermes', mismatch.stdout)
            subprocess.run(command + ['restore'] + args, check=True, capture_output=True)
            result = json.loads(live.read_text())
            self.assertIs(result['display']['message_reactions'], False)
            self.assertEqual(result['auth'], {'fixture': 'local-only'})
            subprocess.run(command + ['check'] + args, check=True, capture_output=True)

    def test_hermes_shared_skills_are_additive_and_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            live, saved = [Path(directory) / name for name in ('live.json', 'saved.json')]
            live.write_text(json.dumps({'skills': {'external_dirs': ['profile-skills']}}))
            saved.write_text(json.dumps({'skills': {'create_dir': '~/.agents/skills', 'external_dirs': ['~/.agents/skills']}}))
            command = [sys.executable, str(ROOT / 'scripts/hermes-settings.py'), 'restore', '--skills-only', '--live', str(live), '--snapshot', str(saved)]
            mismatch = subprocess.run([arg if arg != 'restore' else 'check' for arg in command], capture_output=True, text=True)
            self.assertNotEqual(mismatch.returncode, 0)
            self.assertIn('docs/hermes-preferences.md', mismatch.stdout)
            self.assertNotIn('dot hermes', mismatch.stdout)
            subprocess.run(command, check=True, capture_output=True)
            before = live.read_bytes()
            subprocess.run(command, check=True, capture_output=True)
            self.assertEqual(before, live.read_bytes())
            self.assertEqual(json.loads(before)['skills']['external_dirs'], ['profile-skills', '~/.agents/skills'])

    def test_refresh_refuses_missing_or_stale_policy_before_installer(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for folder in ('scripts', 'agents', 'config'):
                (root / folder).mkdir()
            for file in ('scripts/gen-skillsfile.py', 'scripts/skill_lock_names.py', 'agents/.skill-lock.json', 'Skillsfile'):
                shutil.copyfile(ROOT / file, root / file)
            # Resolution uses installed folder names; a fixture copy avoids real updates.
            shutil.copytree(ROOT / 'agents/skills', root / 'agents/skills')
            policy = root / 'config/skills-refresh-holds.json'
            command = [sys.executable, str(root / 'scripts/gen-skillsfile.py'), '--check']
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
            shutil.copyfile(ROOT / 'config/skills-refresh-holds.json', policy)
            subprocess.run(command, check=True, capture_output=True)
            policy.write_text(json.dumps({'not-a-real-skill': 'fixture'}))
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
            marker = root / 'installer-called'
            fake = root / 'npx'; fake.write_text('#!/bin/sh\ntouch "' + str(marker) + '"\n'); fake.chmod(0o755)
            env = dict(os.environ, NPX=str(fake), PYTHON_BIN=sys.executable)
            self.assertNotEqual(subprocess.run(['bash', str(root / 'Skillsfile')], env=env, capture_output=True).returncode, 0)
            self.assertFalse(marker.exists())

    @unittest.skipUnless(sys.platform == 'darwin', 'macOS preference tools required')
    def test_dock_home_paths_are_portable_without_removing_public_filter(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'macos').mkdir()
            (root / '.node-version').write_text((ROOT / '.node-version').read_text())
            dock = root / 'macos/dock-backup.plist'
            dock.write_bytes(plistlib.dumps({'persistent-apps': [{'tile-data': {'file-data': {'_CFURLString': Path.home().as_uri() + '/Apps/Fixture%20App.app/'}}}], 'persistent-others': []}))
            env = dict(os.environ, DOTFILES=str(root))
            subprocess.run(['/bin/bash', str(ROOT / 'scripts/sanitize-app-prefs.sh')], env=env, check=True, capture_output=True)
            data = plistlib.loads(dock.read_bytes())
            self.assertEqual(data['persistent-apps'][0]['tile-data']['file-data']['_CFURLString'], 'file://__HOME__/Apps/Fixture App.app/')
            self.assertNotIn('persistent-others', data)


if __name__ == '__main__':
    unittest.main()
