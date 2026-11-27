#!/usr/bin/env bash
# Read-only status; temporary inspection files never replace live preferences.
case "${OS:-}:$(uname -s)" in
  Windows_NT:*|*:MINGW*|*:MSYS*) echo 'On Windows run dot setup-status.' >&2; exit 2 ;;
esac
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
command -v python3 >/dev/null 2>&1 || {
    echo 'UNKNOWN: Python 3 is unavailable; install core tools with make brew-core, then retry setup-status.' >&2
    exit 2
}
exec python3 -B "$SCRIPT_DIR/setup_status.py" "$@"
