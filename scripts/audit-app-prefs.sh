#!/usr/bin/env bash
# Scan app/macOS preference snapshots for license keys, tokens, emails, account
# IDs, and hardcoded home paths. Run after `make backup` (Makefile invokes this).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
ROOTS=("$DOTFILES/apps" "$DOTFILES/macos" "$DOTFILES/services")
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

issues=0

report() {
  printf '  ✗ %s\n' "$1"
  issues=$((issues + 1))
}

has_any_root=0
for root in "${ROOTS[@]}"; do
  [[ -d "$root" ]] && has_any_root=1
done

if (( ! has_any_root )); then
  echo "audit-app-prefs: no preference roots found — nothing to scan"
  exit 0
fi

echo "Auditing app/macOS preference snapshots …"

APPS="$DOTFILES/apps"
if [[ -d "$APPS" ]]; then
  [[ ! -e "$APPS/dato/dato.plist" ]] || report "personal Dato time-zone snapshot is excluded"
  # Never track these (gitignore); flag if they appear anyway.
  if [[ -e "$APPS/sublime-text/Theme - Monokai Pro.sublime-settings" ]]; then
    report "forbidden path present (vault-only): apps/sublime-text/Theme - Monokai Pro.sublime-settings"
  fi
  if [[ -d "$APPS/shottr" ]]; then
    while IFS= read -r -d '' f; do
      rel="${f#"$DOTFILES/"}"
      [[ "$rel" == "apps/shottr/README.md" ]] && continue
      report "forbidden path present (vault-only): $rel"
    done < <(/usr/bin/find "$APPS/shottr" -mindepth 1 -type f -print0 2>/dev/null)
  fi
fi

DOCK_PLIST="$DOTFILES/macos/dock-backup.plist"
if [[ -f "$DOCK_PLIST" ]] &&
  plutil -p "$DOCK_PLIST" 2>/dev/null | rg -q '^[[:space:]]+"(book|persistent-others)" =>'; then
  report "non-portable Dock bookmark/folder data: macos/dock-backup.plist"
fi

scan_file() {
  local f="$1" rel scan tmp pattern
  rel="${f#"$DOTFILES"/}"
  scan="$f"

  case "$f" in
    *.plist)
      tmp="$TMPDIR/${rel//\//__}.xml"
      if ! plutil -convert xml1 -o "$tmp" "$f" 2>/dev/null; then
        report "unreadable or malformed plist: $rel"
        return 0
      fi
      scan="$tmp"
      ;;
  esac

  if [[ "$rel" == "apps/zed/settings.json" ]] &&
    rg -q '"mode"[[:space:]]*:[[:space:]]*"bypassPermissions"' "$scan" 2>/dev/null; then
    report "unsafe external-agent authorization mode: $rel"
  fi

  if [[ "$rel" == "apps/zed/settings.json" ]] &&
    rg -q '^  "(agent|context_servers)"[[:space:]]*:|"(default_config_options|favorite_config_option_values)"[[:space:]]*:' "$scan" 2>/dev/null; then
    report "non-portable Zed agent runtime state: $rel"
  fi

  if rg -qi 'Paddle-|ZephyrSyncKey|SUUpdateGroupIdentifier|MenuBarItemManager\.|KnownDisplays|DisplayIceBarConfigurations|GlobalDisplayConfiguration|NewItemsPlacementData|savedPipelines|"(cSpell\.words|chat\.tools\..*autoApprove|.*cloudProject|.*projectId)"|bypassPermissions' "$scan" 2>/dev/null; then
    report "non-public identity, inventory, or editor authorization fields: $rel"
  fi

  pattern='license_key|"kc-license"|ghp_[A-Za-z0-9]+|glpat-[A-Za-z0-9_-]+|sk-ant-[A-Za-z0-9_-]+|[a-z_]*api_key"?[[:space:]]*:[[:space:]]*"|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|/Users/[^/[:space:]<"]+|/var/folders/[^/[:space:]<"]+|OneDrive-[A-Za-z0-9._@-]+'

  if rg -qi "$pattern" "$scan" 2>/dev/null; then
    report "private or machine-specific content: $rel"
  fi
}

for root in "${ROOTS[@]}"; do
  [[ -d "$root" ]] || continue
  while IFS= read -r -d '' f; do
    case "$f" in
      */shottr/*) continue ;;
    esac
    scan_file "$f"
  done < <(/usr/bin/find "$root" -type f \( \
    -name '*.json' -o -name '*.sublime-settings' -o -name '*.sublime-keymap' \
    -o -name '*.sublime-snippet' -o -name '*.sublime-macro' -o -name '*.palettes' \
    -o -name '*.py' -o -name '*.plist' -o -name '*.xml' -o -name '*.sh' \
    -o -name 'document.wflow' \
  \) -print0 2>/dev/null)
done

if (( issues > 0 )); then
  printf '\n%d issue(s). Fix or move to ~/.secrets/ + backup manifest, then re-run.\n' "$issues"
  exit 1
fi

echo "  ✓ no issues in app/macOS preference snapshots"
