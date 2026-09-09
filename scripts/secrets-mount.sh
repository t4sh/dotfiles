#!/usr/bin/env bash
# Verify and open the newest completed portable recovery DMG in Finder.

set -euo pipefail

LOCAL_DIR="${DOTFILES_LOCAL_DIR:-$HOME/.dotfiles-local}"
DEST_CACHE="$LOCAL_DIR/backup.destination"

case "${1:-}" in
  -h|--help)
    echo "usage: secrets-mount.sh [vault-destination]"
    exit 0
    ;;
esac

DEST="${1:-${DOTFILES_BACKUP_DEST:-}}"
if [[ -z "$DEST" && -f "$DEST_CACHE" ]]; then
  DEST="$(<"$DEST_CACHE")"
fi
[[ -n "$DEST" ]] || {
  echo "vault destination is not configured — set DOTFILES_BACKUP_DEST, pass it as an argument, or create $DEST_CACHE" >&2
  exit 1
}
DEST="${DEST/#\~/$HOME}"
[[ "$DEST" == /* && -d "$DEST" ]] || {
  echo "vault destination must be an existing absolute directory: $DEST" >&2
  exit 1
}
DEST="$(cd -- "$DEST" && pwd -P)"
VAULT=""
while IFS= read -r candidate; do
  candidate_base="${candidate%.dmg}"
  if [[ -f "$candidate_base.json" && -f "$candidate_base.sha256" ]]; then
    VAULT="$candidate"
    break
  fi
done < <(
  find "$DEST" -maxdepth 1 -type f \
    -name 'DotfilesSecrets-????????-??????.dmg' -print | LC_ALL=C sort -r
)
[[ -n "$VAULT" && -f "$VAULT" ]] || {
  echo "no completed portable vault set found in $DEST — run 'make secrets-backup'" >&2
  exit 1
}
CHECKSUM="${VAULT%.dmg}.sha256"

read -r expected recorded_filename _ < "$CHECKSUM"
[[ "$expected" =~ ^[[:xdigit:]]{64}$ ]] || {
  echo "invalid portable vault checksum: $CHECKSUM" >&2
  exit 1
}
[[ "$recorded_filename" == "$(basename "$VAULT")" ]] || {
  echo "portable vault checksum names the wrong image: $CHECKSUM" >&2
  exit 1
}
actual="$(shasum -a 256 "$VAULT" | awk '{print $1}')"
[[ "$expected" == "$actual" ]] || {
  echo "portable vault checksum mismatch: $VAULT" >&2
  exit 1
}
open "$VAULT"
