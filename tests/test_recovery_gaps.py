#!/usr/bin/env python3
"""Recovery regression tests in isolated homes; no real credentials or apps."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root/'home'; self.home.mkdir()
        self.repo = self.root/'repo'; (self.repo/'scripts').mkdir(parents=True)
        self.envdir = self.home/'.secrets/config/env'; self.envdir.mkdir(parents=True)
        self.env = {**os.environ, 'HOME':str(self.home), 'DOTFILES':str(self.repo)}
        for name in ('link.sh','validate-manifests.sh','migrate-shell-env.py','post-vault.sh'):
            shutil.copyfile(ROOT/'scripts'/name,self.repo/'scripts'/name)

    def run_script(self, name, *args, **kwargs):
        return subprocess.run(['python3' if name.endswith('.py') else 'bash',str(self.repo/'scripts'/name),*args],
                              env=kwargs.get('env',self.env),text=True,capture_output=True)

    def test_legacy_shell_migration_preserves_backup_and_is_idempotent(self):
        legacy=self.home/'.secrets/env.sh'; legacy.write_bytes(b'export EXA_API_KEY="fixture-only"\n')
        backup=self.envdir/'fixture-backup.env'; backup.write_bytes(b'BACKUP=fixture-unchanged\n')
        before=backup.read_bytes()
        for _ in range(2):
            result=self.run_script('migrate-shell-env.py')
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertIn(b'fixture-only', legacy.read_bytes())
            self.assertNotIn(b'EXA_API_KEY', (self.envdir/'shell.env').read_bytes())
            self.assertNotIn('fixture-only',result.stdout+result.stderr)
        self.assertEqual((self.envdir/'shell.env').stat().st_mode & 0o777,0o600)
        self.assertEqual(backup.read_bytes(),before)
        (self.repo/'symlinks.tsv').write_text('$HOME/.secrets/config/env/shell.env\t$HOME/.secrets/env.sh\n')
        result=self.run_script('link.sh',env={**self.env,'DOTFILES_STRICT_LINK':'1'})
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertTrue(legacy.is_symlink())
        self.assertNotIn(b'EXA_API_KEY',legacy.read_bytes())
        copies=list((self.home/'.secrets/recovery/link-backups').rglob('env.sh'))
        self.assertEqual(len(copies),1)
        self.assertIn(b'fixture-only',copies[0].read_bytes())
        self.assertEqual(backup.read_bytes(),before)
        self.assertEqual(self.run_script('migrate-shell-env.py').returncode,0)

    def test_migration_conflict_keeps_both_files_and_hides_contents(self):
        legacy=self.home/'.secrets/env.sh'; legacy.write_text('LEGACY=old-fixture\n')
        canonical=self.envdir/'shell.env'; canonical.write_text('CURRENT=new-fixture\n')
        result=self.run_script('migrate-shell-env.py')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(legacy.read_text(),'LEGACY=old-fixture\n')
        self.assertEqual(canonical.read_text(),'CURRENT=new-fixture\n')
        self.assertNotIn('old-fixture',result.stdout+result.stderr)
        self.assertNotIn('new-fixture',result.stdout+result.stderr)

    def test_identical_legacy_and_canonical_files_require_reconciliation(self):
        legacy = self.home / '.secrets/env.sh'
        canonical = self.envdir / 'shell.env'
        backup = self.envdir / 'fixture-backup.env'
        backup.write_bytes(b'BACKUP=fixture-unchanged\n')
        for contents in (b'export EXA_API_KEY="fixture-only"\n', b'EDITOR=fixture-editor\n'):
            with self.subTest(contents=contents):
                legacy.write_bytes(contents)
                canonical.write_bytes(contents)
                result = self.run_script('migrate-shell-env.py')
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(legacy.read_bytes(), contents)
                self.assertEqual(canonical.read_bytes(), contents)
                self.assertEqual(backup.read_bytes(), b'BACKUP=fixture-unchanged\n')
                self.assertNotIn('fixture-', result.stdout + result.stderr)

    def test_existing_canonical_settings_are_preserved_without_legacy_regular_file(self):
        canonical = self.envdir / 'shell.env'
        canonical.write_bytes(b'EDITOR=fixture-editor\n')
        self.assertEqual(self.run_script('migrate-shell-env.py').returncode, 0)
        (self.home / '.secrets/env.sh').symlink_to(canonical)
        self.assertEqual(self.run_script('migrate-shell-env.py').returncode, 0)
        self.assertEqual(canonical.read_bytes(), b'EDITOR=fixture-editor\n')

    def test_new_shell_file_links_and_missing_required_sources_fail(self):
        self.assertEqual(self.run_script('migrate-shell-env.py').returncode,0)
        (self.repo/'symlinks.tsv').write_text('$HOME/.secrets/config/env/shell.env\t$HOME/.secrets/env.sh\n')
        result=self.run_script('link.sh',env={**self.env,'DOTFILES_STRICT_LINK':'1'})
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(self.run_script('link.sh','--check').returncode,0)
        with (self.repo/'symlinks.tsv').open('a') as f: f.write('$DOTFILES/missing\t$HOME/required\n')
        self.assertNotEqual(self.run_script('link.sh',env={**self.env,'DOTFILES_STRICT_LINK':'1'}).returncode,0)

    def test_secret_backups_stay_private_inside_vault_tree(self):
        old=self.home/'.config/env'; old.mkdir(parents=True); (old/'dummy.env').write_text('fixture-secret\n')
        (self.repo/'symlinks.tsv').write_text('$HOME/.secrets/config/env\t$HOME/.config/env\n')
        result=subprocess.run(['bash','-c','umask 022; exec bash "$1"','_',str(self.repo/'scripts/link.sh')],env=self.env,text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stderr)
        copies=list((self.home/'.secrets/recovery/link-backups').rglob('dummy.env'))
        self.assertEqual(len(copies),1)
        self.assertEqual(copies[0].read_text(),'fixture-secret\n')
        self.assertFalse((self.home/'.dotfiles-backup').exists())
        for p in [self.home/'.secrets/recovery',self.home/'.secrets/recovery/link-backups',copies[0].parent]:
            self.assertEqual(p.stat().st_mode & 0o777,0o700)
        self.assertEqual(self.run_script('link.sh').returncode,0)
        self.assertEqual(len(list((self.home/'.secrets/recovery/link-backups').rglob('dummy.env'))),1)

    def test_ordinary_backup_root_is_private_even_with_normal_umask(self):
        (self.repo/'source').write_text('new\n'); (self.home/'target').write_text('old\n')
        (self.repo/'symlinks.tsv').write_text('$DOTFILES/source\t$HOME/target\n')
        result=subprocess.run(['bash','-c','umask 022; exec bash "$1"','_',str(self.repo/'scripts/link.sh')],env=self.env,capture_output=True)
        self.assertEqual(result.returncode,0)
        self.assertEqual((self.home/'.dotfiles-backup').stat().st_mode & 0o777,0o700)

    def test_client_check_rejects_copied_bridges_and_reports_runtime_limits(self):
        pairs=[('config/codex/AGENTS.md','.codex/AGENTS.md'),
               ('agents/AGENTS.md','.claude/CLAUDE.md'),
               ('config/zed/AGENTS.md','.config/zed/AGENTS.md'),
               ('config/opencode/AGENTS.md','.config/opencode/AGENTS.md'),
               ('config/cursor/rulebook.mdc','.cursor/rules/rulebook.mdc'),
               ('config/copilot/copilot-instructions.md','.copilot/copilot-instructions.md'),
               ('config/antigravity/GEMINI.md','.gemini/GEMINI.md')]
        for source,destination in pairs:
            src=self.repo/source; src.parent.mkdir(parents=True,exist_ok=True); src.write_text('fixture bridge\n')
            dst=self.home/destination; dst.parent.mkdir(parents=True,exist_ok=True); dst.write_text(src.read_text())
        command=['bash',str(ROOT/'scripts/check-agent-clients.sh')]
        result=subprocess.run(command,env=self.env,text=True,capture_output=True)
        self.assertNotEqual(result.returncode,0)
        for source,destination in pairs:
            dst=self.home/destination; dst.unlink(); dst.symlink_to(self.repo/source)
        result=subprocess.run(command,env=self.env,text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('harness limits',result.stdout)
        self.assertIn('fresh-session behavior not established',result.stdout)
        for _, destination in pairs[3:]:
            dst=self.home/destination; src=dst.readlink(); dst.unlink()
            result=subprocess.run(command,env=self.env,text=True,capture_output=True)
            self.assertNotEqual(result.returncode,0)
            dst.symlink_to(src)

    def test_client_bridges_are_manifest_owned(self):
        manifest = (ROOT / 'symlinks.tsv').read_text()
        for source, destination in (
            ('config/opencode/AGENTS.md', '.config/opencode/AGENTS.md'),
            ('config/cursor/rulebook.mdc', '.cursor/rules/rulebook.mdc'),
            ('config/copilot/copilot-instructions.md', '.copilot/copilot-instructions.md'),
            ('config/antigravity/GEMINI.md', '.gemini/GEMINI.md'),
        ):
            self.assertIn('$DOTFILES/' + source + '\t$HOME/' + destination, manifest)
            content = (ROOT / source).read_text()
            self.assertIn('~/.agents/skills/init-rulebook/SKILL.md', content)
            self.assertIn('~/.agents/AGENTS.md', content)
            self.assertIn('context compaction', content)
            self.assertNotIn('rules/*.md', content)
        self.assertIn('$DOTFILES/config/opencode/opencode.jsonc\t$HOME/.config/opencode/opencode.jsonc', manifest)
        self.assertIn('alwaysApply: true', (ROOT / 'config/cursor/rulebook.mdc').read_text())
        self.assertIn('$DOTFILES/agents/AGENTS.md\t$HOME/.claude/CLAUDE.md', manifest)

    def test_post_vault_continues_apps_and_clears_pending_only_after_recovery(self):
        fakebin=self.root/'bin'; fakebin.mkdir()
        log=self.root/'make.log'
        (self.repo/'symlinks.tsv').write_text('$HOME/.secrets/config/env/shell.env\t$HOME/.secrets/env.sh\n')
        make=fakebin/'make'
        make.write_text('#!/bin/bash\ntarget="${@: -1}"\nprintf "%s\\n" "$target" >> "$FIXTURE_LOG"\ncase "$target" in\nlink) exec bash "$DOTFILES/scripts/link.sh";;\nssh-setup) exit "${FIXTURE_SSH_EXIT:-0}";;\nesac\n')
        make.chmod(0o700)
        gh=fakebin/'gh'; gh.write_text('#!/bin/sh\nexit "${FIXTURE_GH_EXIT:-1}"\n'); gh.chmod(0o700)
        (self.repo/'scripts/check-keychain-profiles.py').write_text('import os,sys\nsys.exit(int(os.environ.get("FIXTURE_KEYS_EXIT","1")))\n')
        env={**self.env,'PATH':str(fakebin)+':'+os.environ['PATH'],'FIXTURE_LOG':str(log),'DOTFILES_STATE_DIR':str(self.root/'state')}
        result=self.run_script('post-vault.sh',env=env)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('restore-apps',log.read_text())
        self.assertNotIn('ssh-setup',log.read_text())
        pending=self.root/'state/post-vault.pending'
        self.assertIn('Tool Keychain items',pending.read_text())
        self.assertIn('GitHub CLI authentication',pending.read_text())
        env.update(FIXTURE_KEYS_EXIT='0',FIXTURE_GH_EXIT='0',FIXTURE_SSH_EXIT='1')
        self.assertNotEqual(self.run_script('post-vault.sh',env=env).returncode,0)
        self.assertIn('SSH setup',pending.read_text())
        env['FIXTURE_SSH_EXIT']='0'
        result=self.run_script('post-vault.sh',env=env)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertFalse(pending.exists())

if __name__ == '__main__':
    unittest.main()
