#!/usr/bin/env bash
# Audit repo app/macOS preference snapshots against current system state.
#
# `make backup` is the only thing that refreshes apps/ and macos/ plists, so the
# restore payload silently ages every time a setting changes in an app's UI.
# scripts/audit-app-prefs.sh only checks those snapshots for secrets and machine
# paths; nothing compared them to the live domains. This is the apps.tsv
# equivalent of scripts/audit-brewfile.sh.
#
# `make backup` is capture -> sanitize -> commit, so this mirrors that pipeline:
# live exports are staged into a throwaway DOTFILES tree, run through the real
# scripts/sanitize-app-prefs.sh, and only then compared. That way every key the
# sanitizer strips by design (home paths, bookmarks, license state) is accounted
# for without restating its rules here.
#
# Volatile keys (window geometry, menu-bar placement, launch counters,
# update-check timestamps) are dropped by scripts/lib/plist_drift.py so the
# report only surfaces settings worth re-capturing.
#
# Usage:
#   scripts/audit-apps-drift.sh           check + exit non-zero on drift
#   scripts/audit-apps-drift.sh --check   same; skips cleanly when tooling absent
#   make apps-drift                       same, via Make
#   dot audit-apps-drift                  same, via the dispatcher
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
MANIFEST="${APPS_MANIFEST:-$DOTFILES/apps.tsv}"
HELPER="$DOTFILES/scripts/lib/plist_drift.py"
SANITIZER="$DOTFILES/scripts/sanitize-app-prefs.sh"

CHECK=0
case "${1:-}" in
  -c|--check) CHECK=1 ;;
esac

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  ⚠\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

skip_or_die() {
  [[ $CHECK -eq 1 ]] && { warn "$1 — app preference drift audit skipped"; exit 0; }
  die "$1"
}

command -v python3 >/dev/null 2>&1 || skip_or_die "python3 not on PATH"
[[ -f "$HELPER" ]] || skip_or_die "$HELPER not found"
[[ -f "$MANIFEST" ]] || skip_or_die "$MANIFEST not found"

workdir="$(mktemp -d -t apps-drift.XXXXXX)"
stage="$workdir/stage"
report="$workdir/report"
trap 'rm -rf "$workdir"' EXIT
: > "$report"
mkdir -p "$stage"

# The sanitizer reads .node-version to rewrite Sublime paths; give the throwaway
# tree the same value so it behaves exactly as it does during `make backup`.
cp "$DOTFILES/.node-version" "$stage/.node-version" 2>/dev/null || true

compared=0
drifted=0
missing=0
unconfigured=0

# Pass 1 — stage live exports at their manifest-relative paths.
staged_rows=()
while IFS=$'\t' read -r domain label plist _rest || [[ -n "${domain:-}" ]]; do
  # Skip comments and blank rows, matching the symlinks.tsv/apps.tsv contract.
  case "$domain" in ''|'#'*) continue ;; esac
  [[ -n "$plist" ]] || continue
  label="${label:-$domain}"

  if [[ ! -f "$DOTFILES/$plist" ]]; then
    printf '  ✗ %s — repo snapshot missing: %s\n' "$label" "$plist" >> "$report"
    missing=$((missing + 1))
    continue
  fi

  live="$stage/$plist"
  mkdir -p "$(dirname "$live")"
  if ! defaults export "$domain" "$live" 2>/dev/null; then
    printf '  ⚠ %s (%s) — could not read live domain\n' "$label" "$domain" >> "$report"
    unconfigured=$((unconfigured + 1))
    continue
  fi

  # An empty live domain means the app has no prefs yet (never launched, or
  # pre-restore on a fresh Mac). That is not drift.
  if [[ ! -s "$live" ]] || ! plutil -p "$live" 2>/dev/null | rg -q '[^[:space:]{}]'; then
    printf '  ⚠ %s (%s) — no live preferences yet (app not launched?)\n' "$label" "$domain" >> "$report"
    unconfigured=$((unconfigured + 1))
    rm -f "$live"
    continue
  fi

  staged_rows+=("$domain"$'\t'"$label"$'\t'"$plist")
done < "$MANIFEST"

# Irregular repo-captured surfaces that do not fit apps.tsv.
stage_plist_file() {
  local source="$1" label="$2" plist="$3" identity="$4" live
  if [[ ! -f "$DOTFILES/$plist" ]]; then
    printf '  ✗ %s — repo snapshot missing: %s\n' "$label" "$plist" >> "$report"
    missing=$((missing + 1))
    return
  fi
  if [[ ! -f "$source" ]]; then
    printf '  ⚠ %s — live preferences unavailable\n' "$label" >> "$report"
    unconfigured=$((unconfigured + 1))
    return
  fi
  live="$stage/$plist"
  mkdir -p "$(dirname "$live")"
  cp "$source" "$live"
  staged_rows+=("$identity"$'\t'"$label"$'\t'"$plist")
}

stage_defaults() {
  local domain="$1" label="$2" plist="$3" live
  if [[ ! -f "$DOTFILES/$plist" ]]; then
    printf '  ✗ %s — repo snapshot missing: %s\n' "$label" "$plist" >> "$report"
    missing=$((missing + 1))
    return
  fi
  live="$stage/$plist"
  mkdir -p "$(dirname "$live")"
  if defaults export "$domain" "$live" 2>/dev/null; then
    staged_rows+=("$domain"$'\t'"$label"$'\t'"$plist")
  else
    printf '  ⚠ %s (%s) — could not read live domain\n' "$label" "$domain" >> "$report"
    unconfigured=$((unconfigured + 1))
  fi
}

stage_plist_file \
  "$HOME/Library/Group Containers/group.com.sindresorhus.Dato/Library/Preferences/group.com.sindresorhus.Dato.plist" \
  "Dato" "apps/dato/dato.plist" "dato-file"
stage_defaults "com.apple.Terminal" "Terminal" "apps/terminal/terminal.plist"
stage_defaults "com.apple.dock" "Dock" "macos/dock-backup.plist"
# The public VS Code and Cursor settings files are deliberately curated
# onboarding templates, not faithful projections of the private reference Mac.
# Comparing them with live private profiles would either remain permanently red
# or leak private-only labels and command approvals into the public snapshot.

sublime_live="$HOME/Library/Application Support/Sublime Text/Packages/User"
sublime_stage="$stage/apps/sublime-text"
sublime_enabled=0
if [[ -d "$DOTFILES/apps/sublime-text" && -d "$sublime_live" ]]; then
  mkdir -p "$sublime_stage"
  while IFS= read -r -d '' source; do
    cp "$source" "$sublime_stage/$(basename "$source")"
    sublime_enabled=1
  done < <(find "$sublime_live" -maxdepth 1 -type f \
    \( -name '*.sublime-settings' -o -name '*.sublime-keymap' \
       -o -name '*.sublime-snippet' -o -name '*.sublime-macro' \
       -o -name '*.palettes' -o -name '*.py' \) \
    ! -name 'Theme - Monokai Pro.sublime-settings' -print0)
  if (( ! sublime_enabled )); then
    printf '  ⚠ Sublime Text — no managed live settings found\n' >> "$report"
    unconfigured=$((unconfigured + 1))
  fi
else
  printf '  ⚠ Sublime Text — live settings unavailable\n' >> "$report"
  unconfigured=$((unconfigured + 1))
fi

# Pass 2 — apply the real sanitizer to the staged copies, never to the repo.
if [[ -f "$SANITIZER" ]]; then
  if ! DOTFILES="$stage" bash "$SANITIZER" >"$workdir/sanitize.log" 2>&1; then
    warn "sanitize-app-prefs.sh failed on staged exports; drift may be overstated"
    sed 's/^/    /' "$workdir/sanitize.log" >&2
  fi
else
  warn "$SANITIZER not found; sanitized-by-design keys will look like drift"
fi

# Pass 3 — compare sanitized live exports against the committed snapshots.
for row in ${staged_rows+"${staged_rows[@]}"}; do
  IFS=$'\t' read -r domain label plist <<< "$row"
  compared=$((compared + 1))
  keys="$workdir/${domain}.keys"
  set +e
  python3 "$HELPER" "$stage/$plist" "$DOTFILES/$plist" > "$keys" 2>"$workdir/${domain}.err"
  status=$?
  set -e

  # A drift verdict must come with a key-level report. Empty output alongside
  # exit 1 means the helper itself failed, so never silently call that drift.
  if (( status == 1 )) && [[ -s "$keys" ]]; then
    drifted=$((drifted + 1))
    printf '  ✗ %s (%s) → %s\n' "$label" "$domain" "$plist" >> "$report"
    cat "$keys" >> "$report"
  elif (( status != 0 )); then
    missing=$((missing + 1))
    printf '  ✗ %s (%s) — comparison failed: %s\n' \
      "$label" "$domain" "$(tr '\n' ' ' < "$workdir/${domain}.err")" >> "$report"
  fi
done

if (( sublime_enabled )); then
  while IFS= read -r -d '' repo_file; do
    basename="$(basename "$repo_file")"
    compared=$((compared + 1))
    if [[ ! -f "$sublime_stage/$basename" ]]; then
      drifted=$((drifted + 1))
      printf '  ✗ Sublime Text → apps/sublime-text/%s (repo only)\n' "$basename" >> "$report"
    elif ! cmp -s "$sublime_stage/$basename" "$repo_file"; then
      drifted=$((drifted + 1))
      printf '  ✗ Sublime Text → apps/sublime-text/%s (content differs)\n' "$basename" >> "$report"
    fi
  done < <(find "$DOTFILES/apps/sublime-text" -maxdepth 1 -type f \
    \( -name '*.sublime-settings' -o -name '*.sublime-keymap' \
       -o -name '*.sublime-snippet' -o -name '*.sublime-macro' \
       -o -name '*.palettes' -o -name '*.py' \) \
    ! -name 'Theme - Monokai Pro.sublime-settings' -print0)

  while IFS= read -r -d '' live_file; do
    basename="$(basename "$live_file")"
    if [[ ! -f "$DOTFILES/apps/sublime-text/$basename" ]]; then
      compared=$((compared + 1))
      drifted=$((drifted + 1))
      printf '  ✗ Sublime Text → apps/sublime-text/%s (live only)\n' "$basename" >> "$report"
    fi
  done < <(find "$sublime_stage" -maxdepth 1 -type f -print0)
fi

if (( drifted == 0 && missing == 0 )); then
  ok "app preference snapshots in sync with system state ($compared surface(s) compared)"
  if (( unconfigured > 0 )); then
    info "$unconfigured domain(s) have no live preferences yet"
    rg '^  ⚠' "$report" || true
  fi
  exit 0
fi

warn "app preference snapshot drift detected vs current system state"
echo
info "$compared surface(s) compared; $drifted drifted, $missing unreadable/missing"
echo
cat "$report"
echo
info "recommended fixes"
echo "  - re-capture live preferences into the repo: make backup"
echo "  - or revert unwanted local changes: make restore-apps"
echo "  - machine-local keys belong in scripts/sanitize-app-prefs.sh"
echo "  - volatile keys belong in scripts/lib/plist_drift.py"
exit 1
