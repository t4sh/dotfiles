#!/usr/bin/env bash
# Validate the newest mounted vault snapshot and report its age.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
SOURCE_ROOT="${DOTFILES_RESTORE_SOURCE:-/Volumes/DotfilesSecrets}"
MAX_AGE_DAYS="${DOTFILES_VAULT_MAX_AGE_DAYS:-30}"

[[ "$MAX_AGE_DAYS" =~ ^[1-9][0-9]*$ ]] || {
  echo "DOTFILES_VAULT_MAX_AGE_DAYS must be a positive integer" >&2
  exit 2
}
[[ -d "$SOURCE_ROOT" ]] || {
  echo "vault is not mounted at $SOURCE_ROOT; mount it, then rerun: make secrets-health" >&2
  exit 2
}

stamp="$(find "$SOURCE_ROOT" -maxdepth 1 -type d \
  -name '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]' \
  -exec basename {} \; | LC_ALL=C sort | tail -n 1)"
[[ -n "$stamp" ]] || { echo "no finalized vault snapshots found in $SOURCE_ROOT" >&2; exit 1; }

bash "$DOTFILES/scripts/secrets-restore.sh" --check "$stamp"

snapshot_epoch="$(date -j -f '%Y%m%d-%H%M%S' "$stamp" '+%s' 2>/dev/null || true)"
[[ -n "$snapshot_epoch" ]] || { echo "cannot parse vault snapshot timestamp: $stamp" >&2; exit 2; }
age_days=$(( ($(date +%s) - snapshot_epoch) / 86400 ))
if (( age_days > MAX_AGE_DAYS )); then
  echo "vault snapshot $stamp is ${age_days} days old (limit: ${MAX_AGE_DAYS})" >&2
  exit 1
fi
echo "  ✓ newest vault snapshot is ${age_days} day(s) old (limit: ${MAX_AGE_DAYS})"
