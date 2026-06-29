#!/usr/bin/env bash
# Flush caches, logs, and common daemons after heavy system churn.
# Invoked via `cleanMac` alias → `sudo bash ~/.dotfiles/scripts/clean-mac.sh`.

set -uo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "This script needs sudo. Run via the 'cleanMac' alias."
  exit 1
fi

if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
  TARGET_HOME="$(dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
else
  TARGET_HOME="$HOME"
fi
[[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] || TARGET_HOME="$HOME"

echo "Cleaning up the Mac…"

purge
dscacheutil -flushcache
killall -HUP mDNSResponder       || true
killall -HUP mDNSResponderHelper || true

rm -rf "$TARGET_HOME/Library/Logs"/*
rm -rf /private/var/log/*

killall coreaudiod     || true
killall SystemUIServer || true
killall Finder         || true
killall Dock           || true

echo "Done."
