#!/usr/bin/env bash
# Restore the Dock layout from macos/dock-backup.plist (captured by `make
# backup`). The backup plist is the source of truth for dock state; the
# hardcoded rebuild script lives at macos/dock-dev.sh for fallback / edit
# mode (see header there).
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
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
