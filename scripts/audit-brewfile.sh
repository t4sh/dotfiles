#!/usr/bin/env bash
# Audit the Brewfile against current system state.
#
# This is stricter than `brew bundle check`: it catches both directions of drift:
#   - Declared in Brewfile but not currently present/requested on this Mac.
#   - Installed/requested on this Mac but not declared in Brewfile.
#
# Common causes of drift:
#   - New top-level install never added to Brewfile (`brew install <x>` without
#     a follow-up dump or manual Brewfile entry).
#   - Transitive dependency the user relies on, never elevated to a leaf.
#   - Declared package uninstalled out of band.
#
# Usage:
#   scripts/audit-brewfile.sh             check + exit non-zero on drift
#   scripts/audit-brewfile.sh --check     same; skips cleanly when brew absent
#   make brewfile-audit                   same, via Make
#   dot audit-brewfile                    same, via the dispatcher (scripts/audit-brewfile.sh)
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
BREWFILE="${BREWFILE:-$DOTFILES/Brewfile}"

CHECK=0
case "${1:-}" in
  -c|--check) CHECK=1 ;;
esac

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  ⚠\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

if ! command -v brew >/dev/null 2>&1; then
  [[ $CHECK -eq 1 ]] && { warn "brew not on PATH — Brewfile audit skipped (not bootstrapped)"; exit 0; }
  die "brew not on PATH"
fi
if [[ ! -f "$BREWFILE" ]]; then
  [[ $CHECK -eq 1 ]] && { warn "$BREWFILE not found — Brewfile audit skipped"; exit 0; }
  die "$BREWFILE not found"
fi

tmp="$(mktemp -t Brewfile.dump.XXXXXX)"
actual_norm="$(mktemp -t Brewfile.actual.XXXXXX)"
expected_norm="$(mktemp -t Brewfile.expected.XXXXXX)"
missing_from_system="$(mktemp -t Brewfile.missing-system.XXXXXX)"
missing_from_brewfile="$(mktemp -t Brewfile.missing-brewfile.XXXXXX)"
dump_log="$(mktemp -t Brewfile.dump.log.XXXXXX)"
trap 'rm -f "$tmp" "$actual_norm" "$expected_norm" "$missing_from_system" "$missing_from_brewfile" "$dump_log"' EXIT

normalize_brewfile() {
  # Compare declarations as a sorted multiset, not as generated text.
  # Plain `sort` preserves duplicate/distinct declarations; do not use `sort -u`.
  grep -v '^[[:space:]]*#' "$1" \
    | sed '/^[[:space:]]*$/d' \
    | LC_ALL=C sort
}

if ! env DOTFILES="$DOTFILES" BREWFILE="$BREWFILE" \
  bash "$DOTFILES/scripts/brewfile.sh" dump "$tmp" >"$dump_log" 2>&1; then
  warn "brew bundle dump failed:"
  sed 's/^/    /' "$dump_log" >&2
  die "brewfile audit could not compare current system state"
fi

normalize_brewfile "$BREWFILE" >"$expected_norm"
normalize_brewfile "$tmp" >"$actual_norm"

comm -23 "$expected_norm" "$actual_norm" >"$missing_from_system"
comm -13 "$expected_norm" "$actual_norm" >"$missing_from_brewfile"

if [[ ! -s "$missing_from_system" && ! -s "$missing_from_brewfile" ]]; then
  ok "Brewfile declarations in sync with system state"
  exit 0
fi

warn "Brewfile declaration drift detected vs current system state"

if [[ -s "$missing_from_system" ]]; then
  echo
  info "declared in Brewfile but not installed/requested on this Mac"
  sed 's/^/  - /' "$missing_from_system"
fi

if [[ -s "$missing_from_brewfile" ]]; then
  echo
  info "installed/requested on this Mac but missing from Brewfile"
  sed 's/^/  + /' "$missing_from_brewfile"
fi

echo
info "full normalized diff"
diff -u "$expected_norm" "$actual_norm" || true

echo
info "recommended fixes"
if [[ -s "$missing_from_system" ]]; then
  echo "  - install declared entries: make brew"
  echo "  - or remove unwanted declarations from $BREWFILE"
fi
if [[ -s "$missing_from_brewfile" ]]; then
  echo "  - refresh declarations from this Mac: make backup"
  echo "  - or uninstall unwanted packages/casks/extensions"
fi
exit 1
