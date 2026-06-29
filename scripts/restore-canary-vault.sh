#!/usr/bin/env bash
# Restore Canary Mail config from ~/.secrets/apps/canary-mail/ into the sandbox.
# Quit Canary Mail before running (realm files are locked while the app is open).
#
# Usage: bash scripts/restore-canary-vault.sh
set -euo pipefail

CONTAINER="$HOME/Library/Containers/io.canarymail.mac/Data/Library"
PREFS_DST="$CONTAINER/Preferences/io.canarymail.mac.plist"
DB_DST="$CONTAINER/Application Support/CanaryDB"
SRC="$HOME/.secrets/apps/canary-mail"
SRC_PREFS="$SRC/preferences/io.canarymail.mac.plist"
SRC_REALMS="$SRC/realms"

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  ⚠\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[[ -d "$SRC_REALMS" || -f "$SRC_PREFS" ]] || die "no vault copy at $SRC — run: make backup-canary"

if pgrep -xq "Canary Mail" 2>/dev/null || pgrep -xf ".*Canary Mail.*" 2>/dev/null; then
  warn "Canary Mail appears to be running — quit the app first, then re-run"
  die "refusing to overwrite open realm files"
fi

[[ -d "$CONTAINER" ]] || die "Canary container not found"

info "restoring Canary Mail from $SRC"
mkdir -p "$(dirname "$PREFS_DST")" "$DB_DST"

if [[ -f "$SRC_PREFS" ]]; then
  cp -f "$SRC_PREFS" "$PREFS_DST"
  ok "preferences"
fi

if [[ -d "$SRC_REALMS" ]]; then
  shopt -s nullglob
  for src in "$SRC_REALMS"/*; do
    base="${src##*/}"
    [[ -e "$src" ]] || continue
    rm -rf "${DB_DST:?}/$base"
    cp -a "$src" "$DB_DST/$base"
    ok "realms/$base"
  done
  shopt -u nullglob
fi

echo ""
ok "Canary restore complete — open Canary Mail (re-auth accounts if prompted)"
