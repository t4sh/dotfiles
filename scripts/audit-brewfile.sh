#!/usr/bin/env bash
# Audit the Brewfile against current system state.
#
# Catches "ripgrep-style" gaps: a formula/cask/MAS app installed but not
# declared (or vice versa). Fresh `brew bundle dump` is the source
# of truth; any diff against the committed Brewfile is drift.
#
# Common causes of drift:
#   - new top-level install never added to Brewfile (`brew install <x>` without
#     a follow-up dump)
#   - transitive dep the user actually relies on, never elevated to a leaf
#     (the original ripgrep case — install_receipt had installed_on_request=false
#     so `brew bundle dump` skipped it)
#   - declared package uninstalled out of band
#
#   scripts/audit-brewfile.sh             check + exit non-zero on drift
#   scripts/audit-brewfile.sh --check     same; skips cleanly when brew absent
#                                         (use from hooks / CI / pre-bootstrap)
#   dot audit-brewfile                    same, via the dispatcher
#   make brewfile-audit                   same, via Make
#
# To resolve a real drift:
#   - new top-level install   → brew bundle dump -f --file=Brewfile
#   - transitive dep to keep  → brew install <name>   (flips on-request flag)
#   - declared but not on box → brew bundle install --file=Brewfile
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

# In --check mode (hook / CI / pre-bootstrap) missing tooling means "cannot
# audit yet" — not a failure. Skip cleanly, mirroring audit-skill-licenses.sh.
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
dump_log="$(mktemp -t Brewfile.dump.log.XXXXXX)"
trap 'rm -f "$tmp" "$actual_norm" "$expected_norm" "$dump_log"' EXIT

normalize_brewfile() {
  # Compare declarations as a set, not as generated text. Homebrew/MAS can
  # reorder duplicate-name MAS entries such as old/new Keynote IDs without any
  # real package drift. Plain `sort` preserves duplicate/distinct declarations;
  # do not use `sort -u`.
  grep -v '^[[:space:]]*#' "$1" \
    | sed '/^[[:space:]]*$/d' \
    | LC_ALL=C sort
}

if ! brew bundle dump --file="$tmp" --force >"$dump_log" 2>&1; then
  warn "brew bundle dump failed:"
  sed 's/^/    /' "$dump_log" >&2
  die "brewfile audit could not compare current system state"
fi

normalize_brewfile "$BREWFILE" >"$expected_norm"
normalize_brewfile "$tmp" >"$actual_norm"

if diff -q "$expected_norm" "$actual_norm" >/dev/null 2>&1; then
  ok "Brewfile declarations in sync with system state"
  exit 0
fi

warn "Brewfile declaration drift detected vs current system state:"
diff -u "$expected_norm" "$actual_norm" || true
echo
info "to resolve:"
echo "  - new top-level install   → brew bundle dump -f --file=\"$BREWFILE\""
echo "  - transitive dep to keep  → brew install <name>   (flips on-request flag)"
echo "  - declared but not on box → brew bundle install --file=\"$BREWFILE\""
exit 1
