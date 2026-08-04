#!/usr/bin/env bash
# After ~/.secrets lands: restore backup ownership, wire consumers, prove SSH,
# and restore vault-backed preferences.
#
# Prerequisite (operator): vault mount → rsync → make secrets-pass-import
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
SHOTTR_PLIST="$HOME/.secrets/apps/shottr/cc.ffitch.shottr.plist"
CANARY_SRC="$HOME/.secrets/apps/canary-mail"
CANARY_PREFS="$CANARY_SRC/preferences/io.canarymail.mac.plist"
CANARY_REALMS="$CANARY_SRC/realms"
CANARY_CONTAINER="$HOME/Library/Containers/io.canarymail.mac/Data/Library"

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  ⚠\033[0m %s\n' "$*"; }

run_make() {
  make -C "$DOTFILES" --no-print-directory "$@"
}

info "post-vault: install backup manifest"
run_make secrets-manifest

info "post-vault: link all declared consumers"
DOTFILES_STRICT_LINK=1 run_make link

info "post-vault: ssh-setup"
run_make ssh-setup

if [[ -f "$SHOTTR_PLIST" ]]; then
  info "post-vault: restore-shottr"
  run_make restore-shottr
else
  warn "Shottr vault payload absent — skipped"
fi

if [[ -f "$CANARY_PREFS" && -d "$CANARY_REALMS" ]]; then
  if [[ -d "$CANARY_CONTAINER" ]]; then
    info "post-vault: restore-canary"
    run_make restore-canary
  else
    warn "Canary vault present but app never launched — launch once, then: make restore-canary"
  fi
else
  warn "Canary vault payload absent — skipped"
fi

info "post-vault: restore-apps"
run_make restore-apps

ok "post-vault complete"

cat <<'EOF'

GUI leftovers:
  • App Store → make brew-mas
  • Import Raycast / Transmit (/ VS Code MCP) from ~/.secrets/apps/
  • Sign into apps; Hammerspoon Login + Accessibility
  • Dato once → make restore-apps   (if used)
  • make default-apps && make doctor
  • make skills
  • make terminal   (not from Terminal.app)

EOF
