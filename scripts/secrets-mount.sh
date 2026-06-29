#!/usr/bin/env bash
# Open the secrets vault in Finder. Destination comes from the cache written
# by secrets-backup.sh — never hardcoded.

set -euo pipefail

LOCAL_DIR="${DOTFILES_LOCAL_DIR:-$HOME/.dotfiles-local}"
DEST_CACHE="$LOCAL_DIR/backup.destination"

[[ -f "$DEST_CACHE" ]] || { echo "no $DEST_CACHE — run 'make secrets-backup' first"; exit 1; }
DEST="$(<"$DEST_CACHE")"
VAULT="$DEST/DotfilesSecrets.sparseimage"

[[ -f "$VAULT" ]] || { echo "vault not found: $VAULT"; exit 1; }
open "$VAULT"
