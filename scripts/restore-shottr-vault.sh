#!/usr/bin/env bash
# Restore Shottr preferences from ~/.secrets/apps/shottr/ (includes license key).
#
# Usage: bash scripts/restore-shottr-vault.sh
set -euo pipefail

DOMAIN="cc.ffitch.shottr"
SRC="$HOME/.secrets/apps/shottr/${DOMAIN}.plist"

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m  ✓\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[[ -f "$SRC" ]] || die "no vault copy at $SRC — run: make backup-shottr"

info "restoring Shottr from $SRC"
defaults import "$DOMAIN" "$SRC"
ok "Shottr preferences"

echo ""
ok "Shottr restore complete — open Shottr"
