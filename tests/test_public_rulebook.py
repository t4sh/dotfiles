"""Fail-closed public rulebook fixture for index and nested routing drift."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PublicRulebookAudit(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='public-rulebook-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        shutil.copytree(ROOT / 'agents', self.root / 'agents')
        (self.root / 'scripts').mkdir()
        shutil.copy2(ROOT / 'scripts/audit-rules.sh', self.root / 'scripts/audit-rules.sh')
        shutil.copy2(ROOT / 'scripts/test-agent-terminal-integration.sh',
                     self.root / 'scripts/test-agent-terminal-integration.sh')

    def audit(self):
        bash = (str(Path(os.environ.get('ProgramFiles', 'C:/Program Files')) / 'Git/bin/bash.exe')
                if os.name == 'nt' else 'bash')
        return subprocess.run([bash, (self.root / 'scripts/audit-rules.sh').as_posix()],
                              env={**os.environ, 'DOTFILES': self.root.as_posix()},
                              capture_output=True, text=True, encoding='utf-8')

    def test_duplicate_index_entry_fails(self):
        index = self.root / 'agents/AGENTS.md'
        text = index.read_text(encoding='utf-8')
        entry = '- [Core principles](./rules/00-core.md)'
        self.assertIn(entry, text)
        index.write_bytes(text.replace(entry, entry + '\n' + entry, 1).encode('utf-8'))
        result = self.audit()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('duplicate top-level rule', result.stderr)

    def test_unlinked_nested_route_fails(self):
        route = self.root / 'agents/rules/routing/forgotten.md'
        route.write_bytes(b'# Fixture\n')
        result = self.audit()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('unlinked reference', result.stderr)

    def test_always_on_membership_and_routing_trigger(self):
        index = (self.root / 'agents/AGENTS.md').read_text(encoding='utf-8')
        always_on = index.split('## Always on', 1)[1].split('## Action-gated', 1)[0]
        for name in ('00-core.md', '01-authorization.md', '03-worktree-hygiene.md',
                     '12-skill-owners.md', '99-anti-patterns.md'):
            self.assertIn(name, always_on)
        self.assertEqual(always_on.count('./rules/'), 5)
        for name in ('10-design-posture.md', '11-skill-routing.md'):
            self.assertNotIn(name, always_on)
        trigger = ('Activate for selections starting from rule 12, overlapping skill choices, '
                   'named skill requests, or cross-skill references')
        self.assertIn('## ' + trigger, index)
        router = (self.root / 'agents/rules/11-skill-routing.md').read_text(encoding='utf-8')
        self.assertTrue(router.splitlines()[2].startswith(trigger))

    def test_absent_skill_owner_fails(self):
        owners = self.root / 'agents/rules/12-skill-owners.md'
        text = owners.read_text(encoding='utf-8')
        self.assertIn('`diagnosing-bugs`', text)
        owners.write_bytes(text.replace('`diagnosing-bugs`', '`missing-owner`', 1).encode('utf-8'))
        result = self.audit()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('skill router names unavailable, non-retired skill: missing-owner', result.stderr)

    def test_task_trigger_groups_keep_setup_preview_and_review_distinct(self):
        index = (self.root / 'agents/AGENTS.md').read_text(encoding='utf-8')
        groups = {}
        for heading, body in re.findall(r'^## ([^\n]+)\n(.*?)(?=^## |\Z)', index, re.M | re.S):
            for rule in re.findall(r'\(\./rules/([^/)]+\.md)\)', body):
                groups[rule] = heading
        self.assertNotEqual(groups['20-code-posture.md'], groups['22-environment.md'])
        for task in ('debugging', 'refactoring'):
            self.assertIn(task, groups['20-code-posture.md'])
        for task in ('package', 'runtime', 'dependency', 'setup'):
            self.assertIn(task, groups['22-environment.md'])
        self.assertIn('previews', groups['21-web-stack.md'])
        self.assertNotIn('previews', groups['24-frontend-verification.md'])
        for task in ('review', 'verification'):
            self.assertIn(task, groups['24-frontend-verification.md'])
        self.assertNotIn('repo', groups['25-tech-stack-discovery.md'])

    def test_task_trigger_declaration_drift_fails(self):
        baseline = self.audit()
        self.assertEqual(baseline.returncode, 0, baseline.stdout + baseline.stderr)
        for name in ('20-code-posture.md', '21-web-stack.md', '22-environment.md',
                     '24-frontend-verification.md', '25-tech-stack-discovery.md'):
            with self.subTest(rule=name):
                path = self.root / 'agents/rules' / name
                original = path.read_bytes()
                changed = re.sub(r'^Activate .+$', 'Activate whenever a repository exists.',
                                 original.decode('utf-8'), count=1, flags=re.M)
                path.write_bytes(changed.encode('utf-8'))
                try:
                    result = self.audit()
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(f'{name} task trigger differs', result.stderr)
                finally:
                    path.write_bytes(original)

    def test_terminal_fixture_runs_before_audit_success(self):
        fixture = self.root / 'scripts/test-agent-terminal-integration.sh'
        fixture.write_bytes(b'#!/bin/bash\nprintf "terminal fixture completed\\n"\n')
        result = self.audit()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('terminal fixture completed', result.stdout)
        self.assertLess(result.stdout.index('terminal fixture completed'),
                        result.stdout.index('rulebook in sync'))

    def test_terminal_fixture_failure_blocks_audit_success(self):
        fixture = self.root / 'scripts/test-agent-terminal-integration.sh'
        fixture.write_bytes(b'#!/bin/bash\necho "terminal fixture failed" >&2\nexit 27\n')
        result = self.audit()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('terminal fixture failed', result.stderr)
        self.assertNotIn('rulebook in sync', result.stdout)


if __name__ == '__main__':
    unittest.main()
