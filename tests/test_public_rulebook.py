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
        index.write_text(text.replace(entry, entry + '\n' + entry, 1), encoding='utf-8', newline='\n')
        result = self.audit()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('duplicate top-level rule', result.stderr)

    def test_unlinked_nested_route_fails(self):
        route = self.root / 'agents/rules/routing/forgotten.md'
        route.write_text('# Fixture\n', encoding='utf-8', newline='\n')
        result = self.audit()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('unlinked reference', result.stderr)


if __name__ == '__main__':
    unittest.main()
