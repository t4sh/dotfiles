#!/usr/bin/env bash
# Validate mounted contents, or the closed published image when unmounted.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
SOURCE_ROOT="${DOTFILES_RESTORE_SOURCE:-/Volumes/DotfilesSecrets}"
MAX_AGE_DAYS="${DOTFILES_VAULT_MAX_AGE_DAYS:-30}"
PUBLISHED=0
DEST=""
case "${1:-}" in
  --published) PUBLISHED=1; shift; DEST="${1:-}"; (($# == 0)) || shift ;;
  -h|--help)
    echo "usage: secrets-health.sh [--published [vault-destination]]"
    echo "Default: validate mounted contents, otherwise verify the published image and age."
    exit 0 ;;
esac
(($# == 0)) || { echo "unexpected secrets-health argument" >&2; exit 2; }

[[ "$MAX_AGE_DAYS" =~ ^[1-9][0-9]*$ ]] || {
  echo "DOTFILES_VAULT_MAX_AGE_DAYS must be a positive integer" >&2
  exit 2
}
if (( PUBLISHED )) || [[ ! -d "$SOURCE_ROOT" ]]; then
  DEST="${DEST:-${DOTFILES_BACKUP_DEST:-}}"
  cache="${DOTFILES_LOCAL_DIR:-$HOME/.dotfiles-local}/backup.destination"
  if [[ -z "$DEST" && -f "$cache" ]]; then DEST="$(<"$cache")"; fi
  [[ -n "$DEST" ]] || {
    echo "vault is not mounted and published destination is unconfigured; set DOTFILES_BACKUP_DEST" >&2
    exit 2
  }
  DEST="${DEST/#\~/$HOME}"
  [[ "$DEST" == /* && -d "$DEST" ]] || { echo "published vault destination unavailable" >&2; exit 2; }
  image="$DEST/DotfilesSecrets.dmg"
  if [[ ! -f "$image" ]]; then
    image=""
    while IFS= read -r candidate; do
      if [[ -f "${candidate%.dmg}.json" && -f "${candidate%.dmg}.sha256" ]]; then
        image="$candidate"
        break
      fi
    done < <(find "$DEST" -maxdepth 1 -type f -name 'DotfilesSecrets-????????-??????.dmg' -print | LC_ALL=C sort -r)
  fi
  [[ -n "$image" ]] || { echo "no completed published vault set found" >&2; exit 1; }
  exec python3 "$DOTFILES/scripts/vault-integrity.py" image-health "$image" --max-age-days "$MAX_AGE_DAYS"
fi

stamp="$(find "$SOURCE_ROOT" -maxdepth 1 -type d \
  -name '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]' \
  -exec basename {} \; | LC_ALL=C sort | tail -n 1)"
[[ -n "$stamp" ]] || { echo "no finalized vault snapshots found in $SOURCE_ROOT" >&2; exit 1; }

bash "$DOTFILES/scripts/secrets-restore.sh" --check "$stamp"

age_days="$(python3 "$DOTFILES/scripts/vault-integrity.py" snapshot-age "$stamp" \
  --max-age-days "$MAX_AGE_DAYS")"
echo "  ✓ newest vault snapshot is ${age_days} day(s) old (limit: ${MAX_AGE_DAYS})"
