#!/usr/bin/env bash
# Reconcile the explicitly managed Sublime Text User files in either direction.
# The Monokai Pro license and unrelated User state are never part of this set.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
REPO_DIR="$DOTFILES/apps/sublime-text"
LIVE_DIR="$HOME/Library/Application Support/Sublime Text/Packages/User"
LICENSE_NAME="Theme - Monokai Pro.sublime-settings"

managed_files() {
  local directory="$1"
  [[ -d "$directory" ]] || return 0
  find "$directory" -maxdepth 1 -type f \
    \( -name '*.sublime-settings' -o -name '*.sublime-keymap' \
       -o -name '*.sublime-snippet' -o -name '*.sublime-macro' \
       -o -name '*.palettes' -o -name '*.py' \) \
    ! -name "$LICENSE_NAME" -print0
}

copy_managed() {
  local source="$1" destination="$2" file
  mkdir -p "$destination"
  while IFS= read -r -d '' file; do
    cp -p "$file" "$destination/"
  done < <(managed_files "$source")
}

remove_managed() {
  local directory="$1" file
  while IFS= read -r -d '' file; do
    rm -f "$file"
  done < <(managed_files "$directory")
}

count_managed() {
  local directory="$1" count=0 file
  while IFS= read -r -d '' file; do
    count=$((count + 1))
  done < <(managed_files "$directory")
  printf '%s' "$count"
}

mode="${1:-}"
case "$mode" in
  capture)
    source_dir="$LIVE_DIR"
    destination_dir="$REPO_DIR"
    [[ -d "$source_dir" ]] || {
      echo "  - Sublime Text not captured (User directory unavailable)"
      exit 0
    }
    ;;
  restore)
    source_dir="$REPO_DIR"
    destination_dir="$LIVE_DIR"
    [[ -d "$source_dir" ]] || {
      echo "  - Sublime Text not restored (repo snapshot unavailable)"
      exit 0
    }
    ;;
  *)
    echo "usage: $0 capture|restore" >&2
    exit 2
    ;;
esac

workdir="$(mktemp -d -t sublime-settings.XXXXXX)"
incoming="$workdir/incoming"
previous="$workdir/previous"
trap 'rm -rf "$workdir"' EXIT

copy_managed "$source_dir" "$incoming"
copy_managed "$destination_dir" "$previous"
mkdir -p "$destination_dir"

if [[ "$mode" == restore ]]; then
  homebrew_prefix=""
  while IFS= read -r -d '' file; do
    grep -q '__HOMEBREW_PREFIX__' "$file" || continue
    if [[ -z "$homebrew_prefix" ]]; then
      command -v brew >/dev/null 2>&1 || {
        echo "Homebrew is required to materialize Sublime Text paths" >&2
        exit 1
      }
      homebrew_prefix="$(brew --prefix)"
    fi
    HOMEBREW_PREFIX="$homebrew_prefix" perl -i -pe \
      's/__HOMEBREW_PREFIX__/$ENV{HOMEBREW_PREFIX}/g' "$file"
  done < <(managed_files "$incoming")
fi

publish() {
  remove_managed "$destination_dir"
  copy_managed "$incoming" "$destination_dir"
}

if ! publish; then
  echo "Sublime Text $mode failed; restoring the previous managed set" >&2
  remove_managed "$destination_dir" || true
  copy_managed "$previous" "$destination_dir" || true
  exit 1
fi

echo "  ✓ Sublime Text ($mode: $(count_managed "$destination_dir") managed file(s))"
