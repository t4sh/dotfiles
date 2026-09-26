"""Fail-closed public rulebook fixture for index and nested routing drift."""
import os
from pathlib import Path
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

    def audit(self):
        return subprocess.run(['bash', str(self.root / 'scripts/audit-rules.sh')],
                              env={**os.environ, 'DOTFILES': str(self.root)},
                              capture_output=True, text=True)

    def test_duplicate_index_entry_fails(self):
        index = self.root / 'agents/AGENTS.md'
        text = index.read_text()
        entry = '- [Core principles](./rules/00-core.md)'
        self.assertIn(entry, text)
        index.write_text(text.replace(entry, entry + '\n' + entry, 1))
        result = self.audit()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('duplicate top-level rule', result.stderr)

    def test_unlinked_nested_route_fails(self):
        route = self.root / 'agents/rules/routing/forgotten.md'
        route.write_text('# Fixture\n')
        result = self.audit()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('unlinked reference', result.stderr)


if __name__ == '__main__':
    unittest.main()
