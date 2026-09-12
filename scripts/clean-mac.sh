#!/usr/bin/env bash
# Remove old user log files; daemon resets are an explicit troubleshooting option.
# Safe default is a dry run. Destructive cleanup requires an explicit --yes.

set -euo pipefail

DRY_RUN=1
RESET_SERVICES=0
LOG_AGE_DAYS="${CLEAN_MAC_LOG_AGE_DAYS:-30}"

usage() {
  cat <<'EOF'
Usage: clean-mac.sh [--dry-run | --yes] [--reset-services]

  --dry-run   List user log files older than the retention threshold (default).
  --yes       Delete those old user log files.
  --reset-services  Also purge memory, flush DNS caches, and restart audio,
                    SystemUIServer, Finder and Dock (requires sudo with --yes).

Environment:
  CLEAN_MAC_LOG_AGE_DAYS  Retention threshold in days (default: 30).

This script never deletes /private/var/log.
EOF
}

while (($#)); do
  case "$1" in
    -n|--dry-run) DRY_RUN=1 ;;
    -y|--yes) DRY_RUN=0 ;;
    --reset-services) RESET_SERVICES=1 ;;
    -h|--help|help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

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
  if (( RESET_SERVICES )); then
    echo "Would purge memory, flush DNS caches, and restart mDNSResponder, mDNSResponderHelper, coreaudiod, SystemUIServer, Finder and Dock."
  else
    echo "Log cleanup only; no memory purge or daemon restarts."
  fi
  echo "No files changed. Re-run with --yes to apply the selected actions."
  exit 0
fi

if (( RESET_SERVICES )) && [[ $EUID -ne 0 ]]; then
  echo "--reset-services --yes requires sudo" >&2
  exit 1
fi

if [[ -d "$LOG_ROOT" ]]; then
  echo "Removing user log files older than $LOG_AGE_DAYS days…"
  /usr/bin/find "$LOG_ROOT" -type f -mtime "+$LOG_AGE_DAYS" -print -delete
fi

if (( RESET_SERVICES )); then
  purge

  dscacheutil -flushcache
  killall -HUP mDNSResponder       || true
  killall -HUP mDNSResponderHelper || true
  killall coreaudiod               || true
  killall SystemUIServer           || true
  killall Finder                   || true
  killall Dock                     || true
fi

echo "Cleanup complete. System logs were preserved."
