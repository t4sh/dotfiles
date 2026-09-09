#!/usr/bin/env bash
# Windows uses native entry points; reject before any Unix-path mutation.
case "${OS:-}:$(uname -s)" in
  Windows_NT:*|*:MINGW*|*:MSYS*) echo 'This is a macOS workflow. On Windows run bin/dot.cmd help.' >&2; exit 2 ;;
esac
# Restore the Dock layout from macos/dock-backup.plist (captured by `make
# backup`). The snapshot owns layout and carries a full-domain copy of Dock
# policy because `defaults import` replaces the domain; defaults.sh remains the
# policy authority, and regression tests require overlapping values to agree.
# The hardcoded rebuild script lives at macos/dock-dev.sh for fallback / edit
# mode (see header there).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
PLIST="$DOTFILES/macos/dock-backup.plist"

if [ ! -f "$PLIST" ]; then
    echo "  ⚠ $PLIST not found."
    echo "    Run 'bash macos/dock-dev.sh' to build the dock from the hardcoded list,"
    echo "    then 'make backup' to capture it as dock-backup.plist."
    exit 1
fi

defaults import com.apple.dock "$PLIST"
killall Dock
echo "  ✓ Dock layout restored from dock-backup.plist"
