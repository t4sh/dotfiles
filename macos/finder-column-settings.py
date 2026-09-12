#!/usr/bin/env python3
"""Compatibility entry point; Finder policy is owned by apply-finder-views.py."""
import argparse
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('apply', 'check', 'dry-run'))
    mode = parser.parse_args().mode
    options = {'apply': ['--policy-only'], 'check': ['--check'],
               'dry-run': ['--policy-only', '--dry-run']}[mode]
    return subprocess.call([sys.executable, str(Path(__file__).resolve().parents[1] /
                            'scripts/apply-finder-views.py'), *options])


if __name__ == '__main__':
    raise SystemExit(main())
