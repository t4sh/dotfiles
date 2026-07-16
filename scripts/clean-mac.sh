#!/usr/bin/env bash
# Flush common daemons and optionally remove old user log files.
# Safe default is a dry run. Destructive cleanup requires an explicit --yes.

set -euo pipefail

DRY_RUN=1
LOG_AGE_DAYS="${CLEAN_MAC_LOG_AGE_DAYS:-30}"

usage() {
  cat <<'EOF'
Usage: clean-mac.sh [--dry-run | --yes]

  --dry-run   List user log files older than the retention threshold (default).
  --yes       Delete those old user log files, purge memory, and restart daemons.

Environment:
  CLEAN_MAC_LOG_AGE_DAYS  Retention threshold in days (default: 30).

This script never deletes /private/var/log.
EOF
}

case "${1:---dry-run}" in
  -n|--dry-run) DRY_RUN=1 ;;
  -y|--yes) DRY_RUN=0 ;;
  -h|--help|help) usage; exit 0 ;;
  *) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
esac

[[ "$LOG_AGE_DAYS" =~ ^[0-9]+$ ]] || {
  echo "CLEAN_MAC_LOG_AGE_DAYS must be a non-negative integer" >&2
  exit 1
}

if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
  TARGET_HOME="$(dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
else
  TARGET_HOME="$HOME"
fi
[[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] || {
  echo "could not resolve the target user home" >&2
  exit 1
}

LOG_ROOT="$TARGET_HOME/Library/Logs"

if (( DRY_RUN )); then
  echo "Dry run: user log files older than $LOG_AGE_DAYS days under $LOG_ROOT"
  if [[ -d "$LOG_ROOT" ]]; then
    /usr/bin/find "$LOG_ROOT" -type f -mtime "+$LOG_AGE_DAYS" -print
  fi
  echo "No files changed. Re-run with --yes to clean and restart daemons."
  exit 0
fi

if [[ $EUID -ne 0 ]]; then
  echo "--yes requires sudo: sudo bash ~/.dotfiles/scripts/clean-mac.sh --yes" >&2
  exit 1
fi

if [[ -d "$LOG_ROOT" ]]; then
  echo "Removing user log files older than $LOG_AGE_DAYS days…"
  /usr/bin/find "$LOG_ROOT" -type f -mtime "+$LOG_AGE_DAYS" -print -delete
fi

purge

dscacheutil -flushcache
killall -HUP mDNSResponder       || true
killall -HUP mDNSResponderHelper || true
killall coreaudiod               || true
killall SystemUIServer           || true
killall Finder                   || true
killall Dock                     || true

echo "Cleanup complete. System logs were preserved."
