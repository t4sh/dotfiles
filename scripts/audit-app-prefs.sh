#!/usr/bin/env bash
# Scan app/macOS preference snapshots for license keys, tokens, emails, account
# IDs, and hardcoded home paths. Run after `make backup` (Makefile invokes this).
set -euo pipefail

command -v rg >/dev/null 2>&1 || { echo 'Preference audit requires ripgrep (rg); install it before auditing.' >&2; exit 127; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
ROOTS=("$DOTFILES/apps" "$DOTFILES/macos" "$DOTFILES/services")
AUDIT_TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$AUDIT_TMP_DIR"' EXIT

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
if ! plist_audit="$(python3 "$SCRIPT_DIR/sanitize-app-plists.py" "$DOTFILES" --check 2>&1)"; then
  report "$plist_audit"
fi
# Parse editor JSONC so whitespace, comments and escaped keys cannot hide bypasses.
for editor in zed vscode cursor; do
  f="$APPS/$editor/settings.json"
  [[ -f "$f" ]] || continue
  python3 "$SCRIPT_DIR/public-editor-policy.py" check --editor "$editor" "$f" ||
    report "unsafe public editor trust or confirmation policy: apps/$editor/settings.json"
done

if [[ -f "$APPS/cursor/cli-config.json" ]]; then
  python3 "$SCRIPT_DIR/cursor-cli-settings.py" audit --snapshot "$APPS/cursor/cli-config.json" || report "invalid Cursor CLI attribution snapshot"
fi
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
      tmp="$AUDIT_TMP_DIR/${rel//\//__}.xml"
      if ! plutil -convert xml1 -o "$tmp" "$f" 2>/dev/null; then
        report "unreadable or malformed plist: $rel"
        return 0
      fi
      scan="$tmp"
      ;;
  esac

  # Backup sanitation must not publish malformed editor snapshots. Reuse Zed's
  # JSONC reader so comments/trailing commas remain valid and capture fails closed.
  case "$rel" in
    apps/zed/settings.json|apps/zed/keymap.json)
      if ! python3 - "$SCRIPT_DIR/check-zed.py" "$f" <<'PY'
from pathlib import Path
import runpy
import sys

try:
    value = runpy.run_path(sys.argv[1])["read_settings"](Path(sys.argv[2]))
    expected = list if Path(sys.argv[2]).name == "keymap.json" else dict
    if not isinstance(value, expected):
        raise ValueError("wrong Zed snapshot type")
except (OSError, ValueError) as error:
    print("invalid Zed JSONC: " + str(error), file=sys.stderr)
    sys.exit(1)
PY
      then
        report "invalid Zed JSONC: $rel"
      fi
      ;;
  esac

  case "$rel" in
    apps/*.plist)
      if ! python3 "$SCRIPT_DIR/public-plist-bookmarks.py" check "$f"; then
        report "non-portable filesystem bookmark or invalid snapshot: $rel"
      fi
      ;;
  esac

  if [[ "$rel" == "apps/betterzip/betterzip.plist" ]] &&
    ! python3 - "$f" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as stream:
    prefs = plistlib.load(stream)
presets = prefs.get("MIBSavePresets", [])
has_password = any(isinstance(item, dict) and "password" in item for item in presets)
sys.exit(1 if "MIBRegCode" in prefs or has_password else 0)
PY
  then
    report "BetterZip registration or archive password in snapshot: $rel"
  fi

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
