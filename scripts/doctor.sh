#!/usr/bin/env bash
# Read-only preflight checks for a fresh or re-applied Mac bootstrap.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
MANIFEST="$DOTFILES/symlinks.tsv"
WARNINGS=0
FAILURES=0

ok() { printf '  ✓ %s\n' "$1"; }
warn() { printf '  ⚠ %s\n' "$1"; WARNINGS=$((WARNINGS + 1)); }
fail() { printf '  ✗ %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

have() { command -v "$1" >/dev/null 2>&1; }

expand_path() {
  local value="$1"
  value="${value//\$DOTFILES/$DOTFILES}"
  value="${value//\$HOME/$HOME}"
  printf '%s' "$value"
}

check_command() {
  local command_name="$1" label="$2"
  if have "$command_name"; then
    ok "$label"
  else
    warn "$label missing"
  fi
}

echo "Dotfiles doctor"
echo "================"

if xcode-select -p >/dev/null 2>&1; then
  ok "Xcode Command Line Tools installed"
else
  fail "Xcode Command Line Tools missing"
fi

if have brew; then
  ok "Homebrew installed"
  if brew bundle check --file="$DOTFILES/Brewfile" >/dev/null 2>&1; then
    ok "Brewfile entries installed"
  else
    warn "Brewfile has missing installs; run: make brew"
  fi
  if bash "$DOTFILES/scripts/audit-brewfile.sh" --check >/dev/null 2>&1; then
    ok "Brewfile declarations match system state"
  else
    warn "Brewfile drift detected; run: make brewfile-audit"
  fi
else
  fail "Homebrew missing"
fi

check_command duti "duti"
check_command gitleaks "gitleaks"
if [ -d "/Applications/Hammerspoon.app" ] || have hs; then
  ok "Hammerspoon installed"
else
  warn "Hammerspoon missing"
fi
check_command typos "typos"

if have gh; then
  if gh auth status >/dev/null 2>&1; then
    ok "GitHub CLI authenticated"
  else
    warn "GitHub CLI installed but not authenticated"
  fi
else
  warn "GitHub CLI missing"
fi

if have mas; then
  if mas account >/dev/null 2>&1; then
    ok "Mac App Store signed in"
  else
    warn "Mac App Store not signed in or mas cannot read account"
  fi
else
  warn "mas missing"
fi

if [ -d "$HOME/.secrets" ]; then
  ok "$HOME/.secrets exists"
else
  warn "$HOME/.secrets missing; restore vault before secret-backed symlinks work"
fi

if [ -f "$MANIFEST" ]; then
  missing_sources=0
  while IFS=$'\t' read -r src dst; do
    case "${src:-}" in ''|\#*) continue ;; esac
    expanded_src="$(expand_path "$src")"
    expanded_dst="$(expand_path "$dst")"
    if [[ ! -e "$expanded_src" && ! -L "$expanded_src" ]]; then
      printf '    missing source: %s → %s\n' "$expanded_src" "$expanded_dst"
      missing_sources=$((missing_sources + 1))
    fi
  done < "$MANIFEST"
  if (( missing_sources == 0 )); then
    ok "all symlink manifest sources exist"
  else
    warn "$missing_sources symlink source(s) missing"
  fi
else
  fail "symlink manifest missing: $MANIFEST"
fi

printf '\nSummary: %d warning(s), %d failure(s)\n' "$WARNINGS" "$FAILURES"
if (( FAILURES > 0 )); then
  exit 1
fi
