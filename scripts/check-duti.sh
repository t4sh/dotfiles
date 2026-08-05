#!/usr/bin/env bash
# Check live Launch Services handlers against the repo's duti policy.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
SETTINGS="${1:-$DOTFILES/config/duti}"

command -v duti >/dev/null 2>&1 || { echo "duti is not installed" >&2; exit 2; }
[[ -f "$SETTINGS" ]] || { echo "$SETTINGS missing" >&2; exit 2; }

checked=0
drifted=0
unreadable=0
while read -r expected target _role; do
  case "${expected:-}" in ''|'#'*) continue ;; esac
  actual=""
  case "$target" in
    .*) actual="$(duti -x "${target#.}" 2>/dev/null | sed -n '3p' || true)" ;;
    *) actual="$(duti -d "$target" 2>/dev/null | head -n 1 || true)" ;;
  esac
  if [[ -z "$actual" ]]; then
    printf '  ? %s — live handler unavailable\n' "$target"
    unreadable=$((unreadable + 1))
  elif [[ "$actual" == "$expected" ]]; then
    checked=$((checked + 1))
  else
    printf '  ✗ %s: expected %s, got %s\n' "$target" "$expected" "$actual"
    checked=$((checked + 1))
    drifted=$((drifted + 1))
  fi
done < "$SETTINGS"

printf 'Default-app mappings: %d checked, %d drifted, %d unavailable\n' \
  "$checked" "$drifted" "$unreadable"
(( drifted == 0 )) || exit 1
(( unreadable == 0 )) || exit 2
