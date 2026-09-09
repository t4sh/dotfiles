#!/usr/bin/env bash
# Open the legacy mutable sparseimage without changing it.
set -euo pipefail

LOCAL_DIR="${DOTFILES_LOCAL_DIR:-$HOME/.dotfiles-local}"
DEST_CACHE="$LOCAL_DIR/backup.destination"

case "${1:-}" in
  -h|--help)
    echo "usage: secrets-mount-legacy.sh [vault-destination]"
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
VAULT="$DEST/DotfilesSecrets.sparseimage"
[[ -f "$VAULT" ]] || { echo "legacy vault not found: $VAULT"; exit 1; }
open "$VAULT"
