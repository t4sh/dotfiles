#!/usr/bin/env bash
# Copy Shottr preferences (includes kc-license) into ~/.secrets/apps/shottr/.
#
# Usage: bash scripts/backup-shottr-vault.sh
# Then run: make secrets-backup
set -euo pipefail
umask 077

DOMAIN="cc.ffitch.shottr"
SECRETS_ROOT="$HOME/.secrets"
DEST="$SECRETS_ROOT/apps/shottr"
DEST_PLIST="$DEST/${DOMAIN}.plist"
STAGE_DIR=""

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m  ✓\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

command -v defaults >/dev/null 2>&1 || die "defaults not found"
defaults read "$DOMAIN" >/dev/null 2>&1 || die "Shottr prefs not found — install Shottr first (Brewfile cask)"

info "backing up Shottr prefs to $DEST"
mkdir -p "$DEST"
chmod 700 "$SECRETS_ROOT" "$SECRETS_ROOT/apps" "$DEST"
cleanup() {
  local status=$?
  [[ -n "$STAGE_DIR" && -d "$STAGE_DIR" ]] && rm -rf -- "$STAGE_DIR"
  return "$status"
}
trap cleanup EXIT

STAGE_DIR="$(mktemp -d "$DEST/.shottr.tmp.XXXXXX")"
STAGE_PLIST="$STAGE_DIR/${DOMAIN}.plist"
defaults export "$DOMAIN" "$STAGE_PLIST"
chmod 600 "$STAGE_PLIST"
mv "$STAGE_PLIST" "$DEST_PLIST"
rmdir "$STAGE_DIR"
STAGE_DIR=""
trap - EXIT
ok "$(basename "$DEST_PLIST")"

echo ""
ok "Shottr prefs staged under ~/.secrets/apps/shottr/"
echo "  next: run make secrets-backup to write the encrypted sparseimage snapshot"
