#!/usr/bin/env bash
# Restore Shottr preferences from ~/.secrets/apps/shottr/ (includes license key).
#
# Usage: bash scripts/restore-shottr-vault.sh
# Running-app policy: warn, quit, refuse unless DOTFILES_RESTORE_FORCE=1.
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
DOMAIN="cc.ffitch.shottr"
SRC="$HOME/.secrets/apps/shottr/${DOMAIN}.plist"

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m  ✓\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[[ -f "$SRC" ]] || die "no vault copy at $SRC — run: make backup-shottr"

# shellcheck source=scripts/lib/running-app-gate.sh
source "$DOTFILES/scripts/lib/running-app-gate.sh"
trap restore_reopen_apps EXIT
restore_running_app_gate "Shottr:Shottr"

info "restoring Shottr from $SRC"
defaults import "$DOMAIN" "$SRC"
ok "Shottr preferences"

echo ""
ok "Shottr restore complete — open Shottr"
