#!/usr/bin/env python3
"""Read local setup state, aggregate failures, and print explicit next steps."""
import argparse
from collections import defaultdict
import os
from pathlib import Path
import signal
import subprocess
import sys

from app_groups import GROUPS, inventory, selection


def probe(command, root, timeout=30):
    env = dict(os.environ, DOTFILES=str(root), HOMEBREW_NO_AUTO_UPDATE='1',
               PYTHONDONTWRITEBYTECODE='1')
    try:
        with subprocess.Popen(command, cwd=root, env=env, stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL, text=True, start_new_session=True) as process:
            try:
                output, _ = process.communicate(timeout=timeout)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate()
                return None, ''
            return process.returncode, output
    except OSError:
        return None, ''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--groups', default=os.environ.get('APP_GROUPS', 'all'))
    args = parser.parse_args()
    root = Path(os.environ.get('DOTFILES', Path(__file__).resolve().parent.parent))
    try:
        chosen = selection(args.groups)
        _, entries = inventory(root)
    except (OSError, ValueError) as error:
        print('Setup status unavailable: ' + str(error), file=sys.stderr)
        return 2
    # Do not print subprocess output: diagnostics can contain local account data.
    print(f'Setup status (read-only) — APP_GROUPS={args.groups}', flush=True)
    print('Selection is per invocation; use the same APP_GROUPS when installing and checking.')
    failed = 0
    code, output = probe(['brew', 'list', '--cask'], root)
    installed = {line.strip().rsplit('/', 1)[-1] for line in output.splitlines()}
    by_group = defaultdict(list)
    for kind, name, group, _ in entries:
        if kind == 'cask':
            by_group[group].append(name)
    for group in GROUPS:
        apps = by_group[group]
        missing = [name for name in apps if name.rsplit('/', 1)[-1] not in installed]
        if group not in chosen:
            print(f'DEFERRED {group}: not requested; already installed apps are retained')
        elif code != 0:
            failed += 1
            print(f'UNKNOWN  {group}: Homebrew inventory unavailable → make brew-apps APP_GROUPS={group}')
        elif missing:
            failed += 1
            print(f'MISSING  {group}: {len(missing)}/{len(apps)} casks → make brew-apps APP_GROUPS={group}')
            print('         ' + ', '.join(missing))
        else:
            suffix = '; extension checks follow' if group == 'development' else ''
            print(f'PRESENT  {group}: {len(apps)} casks{suffix}')
    checks = [
        ('Selected packages, runtimes, extensions and App Store receipts',
         ['bash', 'scripts/brewfile.sh', 'check-selected'],
         'dot brewfile check-selected; retry the reported package phase', 120),
        ('Configuration links', ['bash', 'scripts/link.sh', '--check'], 'dot link --check; review conflicts before make link', 30),
        ('Automator services', ['bash', 'scripts/check-services.sh'], 'make services-check', 30),
        ('Git hooks', ['bash', 'scripts/check-hooks.sh'], 'make hooks-check', 30),
        ('Skill manifest', ['python3', '-B', 'scripts/gen-skillsfile.py', '--check'], 'make skills', 30),
        ('macOS policy', ['bash', 'macos/defaults.sh', '--check'], 'make macos-check', 30),
        ('All saved preferences (including deferred apps)',
         ['bash', 'scripts/audit-apps-drift.sh', '--check', '--strict'],
         'make apps-drift; review drift before any restore', 120),
    ]
    os.environ['APP_GROUPS'] = args.groups
    for label, command, next_step, timeout in checks:
        code, _ = probe(command, root, timeout)
        if code == 0:
            print(f'PASS     {label}', flush=True)
        else:
            failed += 1
            state = 'UNKNOWN' if code is None else 'REVIEW'
            print(f'{state:8} {label} → {next_step}', flush=True)
    home = Path.home()
    if (home / '.secrets').is_dir():
        print('PRESENT  ~/.secrets directory; contents, decryptability and independent recovery copy unverified')
    else:
        print('MANUAL   Secrets recovery → README recovery steps, then make post-vault')
    if (home / '.dotfiles-local/post-vault.pending').is_file():
        print('REVIEW   Post-vault pending marker exists → make post-vault')
        failed += 1
    print('MANUAL   App Store/vendor sign-ins, paid activation and GUI permissions: verify in each app')
    print('MANUAL   Default-app choices remain separate → make default-apps-check')
    print('NEXT     Full post-vault acceptance → make verify-bootstrap (checks full declared inventory)')
    print(f'Summary: {failed} item(s) need review; manual steps are not certified by this report.')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
