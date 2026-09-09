#!/usr/bin/env bash
# Windows uses native entry points; reject before any Unix-path mutation.
case "${OS:-}:$(uname -s)" in
  Windows_NT:*|*:MINGW*|*:MSYS*) echo 'This is a macOS workflow. On Windows run bin/dot.cmd help.' >&2; exit 2 ;;
esac
# After ~/.secrets lands: wire consumers, prove SSH, restore vault-backed prefs.
#
# Prerequisite (operator): secrets-restore[-apply] → secrets-pass-import
# Usage: make post-vault
#        bash scripts/post-vault.sh
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
SHOTTR_PLIST="$HOME/.secrets/apps/shottr/cc.ffitch.shottr.plist"
CANARY_SRC="$HOME/.secrets/apps/canary-mail"
CANARY_PREFS="$CANARY_SRC/preferences/io.canarymail.mac.plist"
CANARY_REALMS="$CANARY_SRC/realms"
CANARY_CONTAINER="$HOME/Library/Containers/io.canarymail.mac/Data/Library"
DATO_SRC="$DOTFILES/apps/dato/dato.plist"
DATO_CONTAINER="$HOME/Library/Group Containers/group.com.sindresorhus.Dato/Library/Preferences"
DATO_PRIMARY_CONTAINER="$HOME/Library/Containers/com.sindresorhus.Dato/Data/Library/Preferences"
DATO_PRIVATE="$HOME/.secrets/apps/dato/com.sindresorhus.Dato.plist"
STATE_DIR="${DOTFILES_STATE_DIR:-$HOME/.dotfiles-local}"
PENDING_FILE="$STATE_DIR/post-vault.pending"
PENDING=()

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
    PENDING+=("Canary Mail")
  fi
else
  warn "Canary vault payload absent — skipped"
fi

info "post-vault: restore-apps"
run_make restore-apps

if [[ -f "$DATO_PRIVATE" ]]; then
  if [[ -d "$DATO_PRIMARY_CONTAINER" ]]; then
    run_make restore-dato
  else
    warn "Dato private prefs present but app never launched — launch once, then: make restore-dato"
    PENDING+=("Dato primary preferences")
  fi
fi

if [[ -f "$DATO_SRC" && ! -d "$DATO_CONTAINER" ]]; then
  PENDING+=("Dato")
fi

mkdir -p "$STATE_DIR"
if ((${#PENDING[@]} > 0)); then
  pending_tmp="$(mktemp "$STATE_DIR/.post-vault.pending.XXXXXX")"
  if ! { printf '%s\n' "${PENDING[@]}" > "$pending_tmp" &&
         chmod 600 "$pending_tmp" &&
         mv "$pending_tmp" "$PENDING_FILE"; }; then
    rm -f "$pending_tmp"
    echo "failed to publish post-vault pending marker" >&2
    exit 1
  fi
  warn "post-vault automation has pending app restores"
else
  rm -f "$PENDING_FILE"
  ok "post-vault automation complete"
fi

cat <<'EOF'

GUI leftovers:
  • If deferred earlier: App Store sign-in → make brew-mas
  • Import Raycast / Transmit (/ VS Code MCP) from ~/.secrets/apps/
  • Import the saved Thaw profile from ~/.secrets/apps/thaw/ after installing Thaw
  • Sign into apps; Hammerspoon Login + Accessibility
  • Dato once → make restore-apps   (if used)
  • Full Dato settings when present → make restore-dato
  • make default-apps && make verify-bootstrap
  • make terminal   (not from Terminal.app)

EOF

((${#PENDING[@]} == 0))
