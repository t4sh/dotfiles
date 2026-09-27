"""Public port-info and port-reset fixtures; no live listener mutation."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipIf(os.name == 'nt', 'Requires POSIX zsh and executable shell fixtures')
class PublicPorts(unittest.TestCase):
    def shell(self, topic, body, **env):
        return subprocess.run(
            ['zsh', '-f', '-c', f'source "{ROOT}/zsh/lib/{topic}"\n' + body],
            text=True, capture_output=True, env={**os.environ, **env}, timeout=15,
        )

    def test_port_reset_preserves_failures(self):
        result = self.shell('50-functions.zsh', r'''
            _port_reset_one() { print "$1"; [[ "$1" != 4000 ]]; }
            port-reset 4000 5000
        ''')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout.splitlines(), ['4000', '5000'])

    def test_port_info_groups_processes_instead_of_port_ranges(self):
        with tempfile.TemporaryDirectory() as td:
            fakebin = Path(td)
            sudo = fakebin / 'sudo'
            sudo.write_text('''#!/bin/sh
if [ "$PORT_FIXTURE_FAIL" = yes ]; then echo 'fixture permission denied' >&2; exit 1; fi
case "$*" in
  -v) exit 0 ;;
  *-iTCP*) cat <<'EOF'
p11
cnode
f1
n127.0.0.1:4168
f2
n127.0.0.1:4168
p12
cControlCenter
f1
n*:3000
p13
cnode
f1
n[::1]:3001
p14
cnext-server
f1
n*:9000
p15
cpython3
f1
n127.0.0.1:8000
p16
cvanished
f1
n*:6000
p17
cpython
n127.0.0.1:65377
p18
cnode
n*:3107
EOF
  ;;
  *'-d cwd'*) cat <<'EOF'
p11
n/fixture/project with spaces
p12
n/
p13
n/fixture/tool
p14
n/fixture/next
p15
n/fixture/static
EOF
  ;;
  *) exit 99 ;;
esac
''')
            ps = fakebin / 'ps'
            ps.write_text('''#!/bin/sh
case "$*" in
  *comm=*) cat <<'EOF'
11 /opt/homebrew/bin/node
12 /System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter
13 /opt/homebrew/bin/node
14 next-server
15 /usr/bin/python3
17 /opt/homebrew/bin/python
18 /opt/homebrew/bin/node
EOF
  ;;
  *args=*) cat <<'EOF'
11 node /fixture/node_modules/vite/bin/vite.js --token fixture-secret
12 ControlCenter
13 node /fixture/tool/server.js --token fixture-secret
14 next-server (v16.0.0)
15 python3 -m http.server 8000
17 python -m hermes_cli.main serve
18 node /fixture/node_modules/serve/build/main.js -l 3107
EOF
  ;;
  *) exit 99 ;;
esac
''')
            sudo.chmod(0o755)
            ps.chmod(0o755)
            env = dict(DOTFILES=str(ROOT), PATH=f'{fakebin}:{os.environ["PATH"]}')
            result = self.shell('50-functions.zsh', 'port-info', **env)
            self.assertEqual(result.returncode, 0, result.stderr)
            previews, rest = result.stdout.split('macOS services:')
            system, other = rest.split('Other apps / unknown:')
            for address in ('127.0.0.1:4168', '*:9000', '127.0.0.1:8000', '*:3107'):
                self.assertIn(address, previews)
            self.assertEqual(previews.count('127.0.0.1:4168'), 1)
            self.assertIn('/fixture/project with spaces', previews)
            self.assertIn('*:3000', system)
            self.assertIn('[::1]:3001', other)
            self.assertIn('127.0.0.1:65377', other)
            self.assertIn('unavailable', other)
            self.assertNotIn('fixture-secret', result.stdout + result.stderr)
            filtered = self.shell('50-functions.zsh', 'port-info 4168', **env)
            self.assertEqual(filtered.returncode, 0, filtered.stderr)
            self.assertIn('127.0.0.1:4168', filtered.stdout)
            self.assertNotIn('*:3000', filtered.stdout)
            empty = self.shell('50-functions.zsh', 'port-info 65535', **env)
            self.assertEqual(empty.returncode, 0, empty.stderr)
            self.assertIn('No matching TCP listeners', empty.stdout)
            failed = self.shell('50-functions.zsh', 'port-info', **env, PORT_FIXTURE_FAIL='yes')
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn('permission denied', failed.stderr)
            self.assertNotIn('No matching', failed.stdout)
            for args in ('0', '65536', '3000 invalid'):
                invalid = self.shell('50-functions.zsh', 'port-info ' + args, **env)
                self.assertNotEqual(invalid.returncode, 0)

    def test_port_reset_validates_all_arguments_and_forwards_force(self):
        for arguments, expected in [('3000', ['3000']),
                                    ('3000 8000 4168', ['3000', '8000', '4168']),
                                    ('--force 3000 8000', ['--force 3000', '--force 8000'])]:
            result = self.shell('50-functions.zsh',
                '_port_reset_one() { print -r -- "$*"; }\nport-reset ' + arguments)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.splitlines(), expected)
        for arguments in ('', '3000 invalid', '3000 0', '3000 65536', '--force', '3000 --force'):
            result = self.shell('50-functions.zsh',
                '_port_reset_one() { print called; }\nport-reset ' + arguments)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('called', result.stdout)



if __name__ == '__main__':
    unittest.main()
