#!/usr/bin/env python3
"""Keychain resolution contracts using a fake security executable; no live credentials."""
import importlib.machinery
import importlib.util
import io
import os
from pathlib import Path
import pwd
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]

class KeychainTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / 'bin').mkdir()
        (self.root / 'scripts/lib').mkdir(parents=True)
        self.security = self.root / 'security'
        self.security.write_text('#!/bin/sh\n[ "$1" = find-generic-password ] || exit 3\n[ "$3" = fixture/service ] || exit 4\nprintf fixture-value\n')
        self.security.chmod(0o700)
        helper = (ROOT / 'scripts/lib/keychain.sh').read_text().replace('/usr/bin/security', str(self.security))
        (self.root / 'scripts/lib/keychain.sh').write_text(helper)
        self.env = {**os.environ, 'DOTFILES_SECRETS_DIR': str(self.root)}
        (self.root / 'config/env').mkdir(parents=True)

    def invoke(self, name, *args):
        shutil.copyfile(ROOT / 'bin' / name, self.root / 'bin' / name)
        return subprocess.run(['bash', '-x', str(self.root / 'bin' / name), *args],
                              env=self.env, capture_output=True, text=True)

    def test_reference_resolution_child_isolation_and_exit_status(self):
        for name, key in [('figma', 'FIGMA_TOKEN'), ('typesafe', 'TYPESAFE_API_KEY')]:
            (self.root / f'config/env/{name}.env').write_text(f"export {key}='keychain://fixture/service'\nexport UNRELATED=hidden\n")
            self.env[key] = 'stale-inherited'
            result = self.invoke(name+'-env', '--', 'bash', '-c',
                                 '[[ "${!1}" == fixture-value && -z "${UNRELATED:-}" && "$2" == "two words" ]] || exit 8; exit 17',
                                 '_', key, 'two words')
            self.assertEqual(result.returncode, 17, result.stderr)
            self.assertNotIn('fixture-value', result.stdout + result.stderr)
            self.assertNotIn('stale-inherited', result.stdout + result.stderr)

    def test_denied_missing_empty_keychain_fails_closed_without_logging(self):
        path = self.root / 'config/env/figma.env'
        path.write_text("export FIGMA_TOKEN='keychain://fixture/service'\n")
        self.env['FIGMA_TOKEN'] = 'stale-inherited'
        for body in ('echo leaked-value >&2; exit 44', 'exit 0'):
            self.security.write_text('#!/bin/sh\n'+body+'\n')
            result = self.invoke('figma-env', '--check')
            self.assertEqual(result.returncode, 1)
            self.assertNotIn('leaked-value', result.stdout + result.stderr)
            self.assertNotIn('stale-inherited', result.stdout + result.stderr)

    def test_context7_uses_keychain_with_existing_runtime_contract(self):
        (self.root / 'config/env/context7.env').write_text("export CONTEXT7_API_KEY='keychain://fixture/service'\n")
        node = self.root / 'node'
        node.write_text('#!/bin/bash\n[[ "$CONTEXT7_API_KEY" == fixture-value && "$3" == @upstash/context7-mcp@4.0.3 && "$4" == "two words" ]] || exit 8\nexit 17\n')
        node.chmod(0o700)
        target = self.root / 'npx-real'; target.touch()
        npx = self.root / 'npx'; npx.symlink_to(target)
        self.env.update(NODE_STABLE=str(node), NPX_STABLE=str(npx))
        result = self.invoke('context7-mcp', 'two words')
        self.assertEqual(result.returncode, 17, result.stderr)
        self.assertNotIn('fixture-value', result.stdout + result.stderr)

    def test_generic_profile_parses_without_executing_shell_and_hides_errors(self):
        loader = importlib.machinery.SourceFileLoader('tool_env', str(ROOT / 'bin/tool-env'))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        module = importlib.util.module_from_spec(spec); loader.exec_module(module)
        path = self.root / 'config/env/exa.env'
        path.write_text("export EXA_API_KEY='keychain://fixture/service'\n")
        output = io.StringIO()
        with patch.dict(os.environ, self.env), patch.object(module.sys, 'argv', ['tool-env','exa','--','echo','two words']), \
             patch.object(module.subprocess, 'run', return_value=subprocess.CompletedProcess([],0,'fixture-value\n','')), \
             patch.object(module.os, 'execvpe') as execute, redirect_stdout(output), redirect_stderr(output):
            module.main()
            self.assertEqual(execute.call_args.args[1], ['echo','two words'])
            self.assertEqual(execute.call_args.args[2]['EXA_API_KEY'], 'fixture-value')
        self.assertNotIn('fixture-value', output.getvalue())
        marker=self.root/'executed'
        path.write_text(f'touch {marker}\n')
        result=subprocess.run(['python3',str(ROOT/'bin/tool-env'),'exa','--check'],env=self.env,capture_output=True)
        self.assertNotEqual(result.returncode,0)
        self.assertFalse(marker.exists())

    def invoke_tool_env(self, *args):
        wrapper = self.root / 'bin/tool-env'
        wrapper.write_text((ROOT / 'bin/tool-env').read_text().replace('/usr/bin/security', str(self.security)))
        return subprocess.run([sys.executable, str(wrapper), *args], env=self.env,
                              capture_output=True, text=True, timeout=10)

    def test_existing_tool_env_commands_work_without_adapter_configuration(self):
        self.env['TOOL_ENV_ADAPTERS'] = str(self.root / 'absent-config.tsv')
        self.env['EXA_API_KEY'] = 'stale-inherited'
        (self.root / 'config/env/exa.env').write_text(
            "export EXA_API_KEY='keychain://fixture/service' # inline comment\n"
            'DESCRIPTION="two words"\n')
        result = self.invoke_tool_env('exa', '--', sys.executable, '-c',
            'import os,sys; assert os.environ["EXA_API_KEY"] == "fixture-value"; '
            'assert os.environ["DESCRIPTION"] == "two words"; '
            'assert sys.argv[1] == "two words"; sys.exit(17)', 'two words')
        self.assertEqual(result.returncode, 17, result.stderr)
        self.assertNotIn('fixture-value', result.stdout + result.stderr)
        self.assertEqual(self.env['EXA_API_KEY'], 'stale-inherited')
        result = self.invoke_tool_env('exa', '--check')
        self.assertEqual((result.returncode, result.stdout), (0, 'tool-env: profile ready (values hidden)\n'))

    def test_existing_profile_named_adapter_flag_remains_usable(self):
        self.env['TOOL_ENV_ADAPTERS'] = str(self.root / 'absent-config.tsv')
        (self.root / 'config/env/--adapter.env').write_text('FIXTURE_TOKEN=fixture-value\n')
        result = self.invoke_tool_env('--adapter', '--check')
        self.assertEqual((result.returncode, result.stdout), (0, 'tool-env: profile ready (values hidden)\n'))
        result = self.invoke_tool_env('--adapter', '--', sys.executable, '-c',
            'import os,sys; assert os.environ["FIXTURE_TOKEN"] == "fixture-value"; '
            'assert sys.argv[1] == "two words"; sys.exit(17)', 'two words')
        self.assertEqual(result.returncode, 17, result.stderr)
        self.assertNotIn('fixture-value', result.stdout + result.stderr)

    def test_existing_tool_env_denial_cannot_use_an_inherited_credential(self):
        self.env['EXA_API_KEY'] = 'stale-inherited'
        (self.root / 'config/env/exa.env').write_text("EXA_API_KEY='keychain://fixture/service'\n")
        marker = self.root / 'command-ran'
        for body in ('echo secret-error >&2; exit 44', 'exit 0'):
            self.security.write_text('#!/bin/sh\n' + body + '\n')
            result = self.invoke_tool_env('exa', '--', '/usr/bin/touch', str(marker))
            self.assertEqual(result.returncode, 1)
            self.assertFalse(marker.exists())
            self.assertNotIn('secret-error', result.stdout + result.stderr)
            self.assertNotIn('stale-inherited', result.stdout + result.stderr)

    def configure_adapter(self):
        config = self.root / 'config/tool-env-adapters.tsv'
        config.write_text('fixture-adapter\tDEMO_ENV\tdemo\tlocal-loader.sh\tDEMO_HOST,DEMO_TOKEN\n')
        (self.root / 'local-loader.sh').write_text('[ -f "$DEMO_ENV" ] || exit 8\nexport FIXTURE_LOADER_RAN=yes\n')
        self.env['TOOL_ENV_ADAPTERS'] = str(config)
        self.env['XDG_CONFIG_HOME'] = str(self.root / 'config')
        profile = self.root / ('config/env/' + pwd.getpwuid(os.getuid()).pw_name + '.demo.env')
        profile.write_text("DEMO_HOST=fixture-host\nDEMO_TOKEN='keychain://fixture/service'\n")
        return config, profile

    def test_adapter_uses_configured_consumer_and_private_file_without_skill_assumptions(self):
        self.configure_adapter()
        record = self.root / 'temp-path'
        result = self.invoke_tool_env('--adapter', 'fixture-adapter', '--', sys.executable, '-c',
            'import os,pathlib,stat,sys; p=pathlib.Path(os.environ["DEMO_ENV"]); '
            'assert os.environ["FIXTURE_LOADER_RAN"] == "yes"; '
            'assert "DEMO_TOKEN=\'fixture-value\'" in p.read_text(); '
            'assert stat.S_IMODE(p.stat().st_mode) == 0o600; '
            'assert stat.S_IMODE(p.parent.stat().st_mode) == 0o700; '
            'pathlib.Path(sys.argv[1]).write_text(str(p)); sys.exit(17)', str(record))
        self.assertEqual(result.returncode, 17, result.stderr)
        self.assertNotIn('fixture-value', result.stdout + result.stderr)
        self.assertFalse(Path(record.read_text()).parent.exists())
        result = self.invoke_tool_env('--adapter', 'fixture-adapter', '--check')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_adapter_config_required_fields_and_loader_failure_stop_the_command(self):
        config, profile = self.configure_adapter()
        marker = self.root / 'command-ran'
        self.env['DEMO_TOKEN'] = 'stale-inherited'
        profile.write_text('DEMO_HOST=fixture-host\n')
        result = self.invoke_tool_env('--adapter', 'fixture-adapter', '--', '/usr/bin/touch', str(marker))
        self.assertEqual(result.returncode, 1)
        profile.write_text('DEMO_HOST=fixture-host\nDEMO_TOKEN=fixture-literal\n')
        self.env['TMPDIR'] = str(self.root)
        (self.root / 'local-loader.sh').write_text('exit 23\n')
        result = self.invoke_tool_env('--adapter', 'fixture-adapter', '--', '/usr/bin/touch', str(marker))
        self.assertEqual(result.returncode, 23)
        self.assertEqual(list(self.root.glob('dotfiles-tool-env-*')), [])
        for contents in ('invalid-config\n', 'fixture-adapter\tBASH_ENV\tdemo\tlocal-loader.sh\tDEMO_HOST\n',
                         config.read_text() * 2):
            config.write_text(contents)
            result = self.invoke_tool_env('--adapter', 'fixture-adapter', '--', '/usr/bin/touch', str(marker))
            self.assertEqual(result.returncode, 1)
        self.assertFalse(marker.exists())

if __name__ == '__main__':
    unittest.main()
