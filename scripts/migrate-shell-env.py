#!/usr/bin/env python3
"""Prepare the canonical shell file after vault recovery, without logging contents."""
import os
from pathlib import Path
import sys


SAFE_SHELL = b"# Non-secret interactive shell settings. Credentials belong in on-demand profiles.\n# Legacy shell content is preserved in ~/.secrets/recovery/link-backups after linking.\n"


def main():
    root = Path.home() / '.secrets'
    old = root / 'env.sh'
    target = root / 'config/env/shell.env'
    try:
        if not root.is_dir():
            raise ValueError()
        if target.is_symlink():
            raise ValueError()
        if old.is_symlink() and old.resolve() != target.resolve():
            raise ValueError()
        if old.exists() and not old.is_symlink() and not old.is_file():
            raise ValueError()
        if target.exists():
            if not target.is_file():
                raise ValueError()
            if old.is_file() and not old.is_symlink() and target.read_bytes() != SAFE_SHELL:
                print('shell-env: legacy and canonical files need review; both preserved. Archive the legacy file locally and keep only non-secret canonical settings before rerunning post-vault.', file=sys.stderr)
                return 1
            print('shell-env: canonical file ready; existing contents preserved')
            return 0
        # Never reactivate code from an older vault: it may export plaintext keys.
        # Keep the original untouched until link.sh archives it inside the vault.
        data = SAFE_SHELL
        target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(target.parent, 0o700)
        fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            with os.fdopen(fd, 'wb') as output:
                output.write(data)
                output.flush()
                os.fsync(output.fileno())
        except OSError:
            target.unlink()
            raise
        print('shell-env: safe shell file prepared; legacy contents will be archived by linking, not activated')
        return 0
    except (OSError, ValueError):
        print('shell-env: preparation failed; details suppressed. Inspect paths locally.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
