#!/usr/bin/env bash
# Copy Shottr preferences (includes kc-license) into ~/.secrets/apps/shottr/.
#
# Usage: bash scripts/backup-shottr-vault.sh
# Then run: make secrets-backup
set -euo pipefail

DOMAIN="cc.ffitch.shottr"
DEST="$HOME/.secrets/apps/shottr"
DEST_PLIST="$DEST/${DOMAIN}.plist"

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m  ✓\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

command -v defaults >/dev/null 2>&1 || die "defaults not found"
defaults read "$DOMAIN" >/dev/null 2>&1 || die "Shottr prefs not found — install Shottr first (Brewfile cask)"

info "backing up Shottr prefs to $DEST"
mkdir -p "$DEST"
defaults export "$DOMAIN" "$DEST_PLIST"
ok "$(basename "$DEST_PLIST")"

echo ""
ok "Shottr prefs staged under ~/.secrets/apps/shottr/"
echo "  next: run make secrets-backup to write the encrypted sparseimage snapshot"
