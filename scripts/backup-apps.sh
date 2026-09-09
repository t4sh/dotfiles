#!/usr/bin/env bash
# Windows uses native entry points; reject before any Unix-path mutation.
case "${OS:-}:$(uname -s)" in
  Windows_NT:*|*:MINGW*|*:MSYS*) echo 'This is a macOS workflow. On Windows run bin/dot.cmd help.' >&2; exit 2 ;;
esac
# Capture repo-managed preferences into a staged tree, validate it, then publish
# the complete snapshot transactionally. A nonzero exit leaves the repo intact.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
SOURCE_DOTFILES="$DOTFILES"
export DOTFILES_PUBLIC_SNAPSHOT=1
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
  # A never-configured domain may export successfully as an empty dictionary.
  # Keep its prior snapshot instead of replacing it with an empty plist.
  if defaults export "$domain" "$STAGE/.defaults-export.plist" 2>/dev/null &&
     plist_view="$(plutil -p "$STAGE/.defaults-export.plist" 2>/dev/null)" &&
     rg -q '[^[:space:]{}]' <<< "$plist_view"; then
    mv "$STAGE/.defaults-export.plist" "$STAGE/$plist"
    ok "$label"
    captured=$((captured + 1))
  else
    warn "$label not captured (app/domain unavailable; prior snapshot retained)"
    skipped=$((skipped + 1))
  fi
done < "$MANIFEST"
info "defaults snapshots: $captured captured, $skipped retained"

# Shared time-zone lists are personal and are omitted from public snapshots.

DATO_PRIMARY="$HOME/Library/Containers/com.sindresorhus.Dato/Data/Library/Preferences/com.sindresorhus.Dato.plist"
if DATO_FORMAT="$(plutil -extract dateTimeFormat raw -o - "$DATO_PRIMARY" 2>/dev/null)"; then
  plutil -create xml1 "$STAGE/apps/dato/display.plist"
  plutil -insert dateTimeFormat -string "$DATO_FORMAT" "$STAGE/apps/dato/display.plist"
  ok "Dato custom date/time format (other primary preferences are not captured)"
else
  warn "Dato custom date/time format unavailable (prior snapshot retained)"
fi

ok "Curated editor and Dock templates retained"
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
  DOTFILES_BREWFILE_PRESERVE_EMPTY_KINDS=1 \
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

Additional private backups:
  - make backup also captures full Dato, Shottr and Deskflow configuration into ~/.secrets.
  - Canary Mail: make backup-canary
  - Thaw: export a profile into ~/.secrets/apps/thaw/ for manual import
  - Transmit / Raycast: export into ~/.secrets/apps/
  - Finish with make secrets-backup to publish an encrypted recovery DMG.
EOF
