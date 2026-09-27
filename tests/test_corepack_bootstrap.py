"""Isolated npm bootstrap checks; never install packages on the test host."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipIf(os.name == 'nt', 'Tests the macOS Brew workflow with POSIX shell fixtures')
class CorepackBootstrapTests(unittest.TestCase):
    def test_enable_after_install_repeat_and_failure_propagation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            tools = root / 'bin'
            tools.mkdir()
            (root / 'Brewfile').write_text('npm "corepack"\n')
            (root / 'retired.tsv').write_text('# fixture\n')
            (root / '.node-version').write_text('v22.23.1\n')
            (root / 'nvm.sh').write_text('nvm() { export PINNED_NODE_ACTIVE=1; }\n')
            brew = tools / 'brew'
            brew.write_text('''#!/bin/sh
cat >/dev/null
[ "${INSTALL_FAIL:-0}" = 0 ] || exit 41
printf 'installed\\n' >> "$EVENTS"
cat > "$FAKE_BIN/corepack" <<'SH'
#!/bin/sh
[ "$PINNED_NODE_ACTIVE" = 1 ] || exit 43
printf '%s\\n' "$*" >> "$EVENTS"
exit "${ENABLE_FAIL:-0}"
SH
chmod +x "$FAKE_BIN/corepack"
''')
            brew.chmod(0o755)
            events = root / 'events'
            env = dict(os.environ, PATH=f'{tools}:/usr/bin:/bin',
                       DOTFILES=str(root), BREWFILE=str(root / 'Brewfile'),
                       DOTFILES_NODE_VERSION_FILE=str(root / '.node-version'),
                       DOTFILES_RETIRED_MAS_IDS=str(root / 'retired.tsv'),
                       DOTFILES_NVM_SH=str(root / 'nvm.sh'),
                       EVENTS=str(events), FAKE_BIN=str(tools))
            def invoke(**overrides):
                return subprocess.run(['bash', str(ROOT / 'scripts/brewfile.sh'), 'npm'],
                                      env={**env, **overrides}, capture_output=True, text=True)
            for _ in range(2):
                result = invoke()
                self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(events.read_text().splitlines(),
                             ['installed', 'enable', 'installed', 'enable'])
            self.assertEqual(invoke(ENABLE_FAIL='42').returncode, 42)
            before = events.read_text()
            self.assertEqual(invoke(INSTALL_FAIL='1').returncode, 41)
            self.assertEqual(events.read_text(), before)


if __name__ == '__main__':
    unittest.main()
