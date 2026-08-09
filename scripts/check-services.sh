#!/usr/bin/env bash
# Compare repo-managed Automator workflows with their installed copies.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
SERVICES_DIR="${DOTFILES_SERVICES_DIR:-$HOME/Library/Services}"

shopt -s nullglob
workflows=("$DOTFILES"/services/*.workflow)
(( ${#workflows[@]} > 0 )) || {
  echo "no managed Automator workflows found under $DOTFILES/services" >&2
  exit 2
}

checked=0
drifted=0
for workflow in "${workflows[@]}"; do
  name="$(basename "$workflow")"
  installed="$SERVICES_DIR/$name"
  checked=$((checked + 1))
  if [[ ! -d "$installed" ]]; then
    echo "  ✗ missing: $name"
    drifted=$((drifted + 1))
  elif ! diff -qr -- "$workflow" "$installed" >/dev/null; then
    echo "  ✗ drifted: $name"
    drifted=$((drifted + 1))
  fi
done

printf 'Automator workflows: %d checked, %d drifted or missing\n' "$checked" "$drifted"
(( drifted == 0 ))
