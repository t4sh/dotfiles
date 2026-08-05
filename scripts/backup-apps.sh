#!/usr/bin/env bash
# Capture repo-managed preferences into a staged tree, validate it, then publish
# the complete snapshot transactionally. A nonzero exit leaves the repo intact.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
SOURCE_DOTFILES="$DOTFILES"
MANIFEST="$DOTFILES/apps.tsv"
STAGE="$(mktemp -d "$DOTFILES/.backup-stage.XXXXXX")"
ROLLBACK="$(mktemp -d "$DOTFILES/.backup-rollback.XXXXXX")"
PUBLISHING=0
TARGETS=(apps macos services Brewfile)

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  ⚠\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

cleanup() {
  local status=$? target i
  trap - EXIT HUP INT TERM
  if (( PUBLISHING )); then
    warn "backup publication failed; restoring the previous repo snapshot"
    for ((i=${#TARGETS[@]} - 1; i >= 0; i--)); do
      target="${TARGETS[$i]}"
      if [[ -e "$ROLLBACK/$target" ]]; then
        rm -rf -- "${DOTFILES:?}/$target"
        mv "$ROLLBACK/$target" "$DOTFILES/$target"
      fi
    done
  fi
  rm -rf -- "$STAGE" "$ROLLBACK"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

bash "$DOTFILES/scripts/validate-manifests.sh" apps

# Seed the complete managed roots so unavailable optional apps retain their last
# known-good snapshot in the staged candidate.
for target in "${TARGETS[@]}"; do
  [[ -e "$DOTFILES/$target" ]] || die "managed backup target missing: $DOTFILES/$target"
  cp -R "$DOTFILES/$target" "$STAGE/$target"
done
cp "$DOTFILES/.node-version" "$STAGE/.node-version"

info "capturing app preferences into a staged snapshot"
captured=0
skipped=0
while IFS=$'\t' read -r domain label plist _; do
  case "${domain:-}" in ''|'#'*) continue ;; esac
  mkdir -p "$(dirname "$STAGE/$plist")"
  if defaults export "$domain" "$STAGE/$plist" 2>/dev/null; then
    ok "$label"
    captured=$((captured + 1))
  else
    warn "$label not captured (app/domain unavailable; prior snapshot retained)"
    skipped=$((skipped + 1))
  fi
done < "$MANIFEST"
info "defaults snapshots: $captured captured, $skipped retained"

DATO_LIVE="$HOME/Library/Group Containers/group.com.sindresorhus.Dato/Library/Preferences/group.com.sindresorhus.Dato.plist"
if [[ -f "$DATO_LIVE" ]]; then
  cp "$DATO_LIVE" "$STAGE/apps/dato/dato.plist"
  ok "Dato"
else
  warn "Dato not captured (prior snapshot retained)"
fi

DOTFILES="$STAGE" bash "$SOURCE_DOTFILES/scripts/sync-sublime-settings.sh" capture

for editor in "Code:VS Code:vscode" "Cursor:Cursor:cursor"; do
  IFS=: read -r directory label repo_name <<< "$editor"
  live="$HOME/Library/Application Support/$directory/User/settings.json"
  if [[ -f "$live" ]]; then
    cp "$live" "$STAGE/apps/$repo_name/settings.json"
    ok "$label settings"
  else
    warn "$label settings not captured (prior snapshot retained)"
  fi
done

defaults export com.apple.dock "$STAGE/macos/dock-backup.plist" 2>/dev/null || \
  die "Dock layout export failed; staged snapshot discarded"
ok "Dock layout"
if defaults export com.apple.Terminal "$STAGE/apps/terminal/terminal.plist" 2>/dev/null; then
  ok "Terminal.app profiles"
else
  warn "Terminal.app profiles not captured (prior snapshot retained)"
fi

for workflow in "$DOTFILES"/services/*.workflow; do
  [[ -e "$workflow" ]] || continue
  name="$(basename "$workflow")"
  source="$HOME/Library/Services/$name"
  [[ -d "$source" ]] || continue
  rm -rf -- "$STAGE/services/$name"
  cp -R "$source" "$STAGE/services/$name"
  ok "Automator workflow $name"
done

DOTFILES="$STAGE" bash "$SOURCE_DOTFILES/scripts/sanitize-app-prefs.sh"
ok "sanitized portable app prefs"
DOTFILES="$SOURCE_DOTFILES" BREWFILE="$SOURCE_DOTFILES/Brewfile" \
  bash "$SOURCE_DOTFILES/scripts/brewfile.sh" dump "$STAGE/Brewfile"
ok "Brewfile"
DOTFILES="$STAGE" bash "$SOURCE_DOTFILES/scripts/audit-app-prefs.sh"

info "publishing complete validated snapshot"
PUBLISHING=1
for target in "${TARGETS[@]}"; do
  mv "$DOTFILES/$target" "$ROLLBACK/$target"
  mv "$STAGE/$target" "$DOTFILES/$target"
done
PUBLISHING=0
rm -rf -- "$ROLLBACK"
ROLLBACK=""
ok "backup snapshot published atomically"

cat <<'EOF'

Manual vault exports still needed:
  - Canary Mail: make backup-canary
  - Shottr: make backup-shottr
  - Transmit / Raycast: export into ~/.secrets/apps/
EOF
