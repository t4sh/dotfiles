#!/usr/bin/env bash
# Remove symlinks declared in symlinks.tsv, only if they still point at our source.
# Idempotent — missing or foreign entries are skipped, not touched.
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
MANIFEST="$DOTFILES/symlinks.tsv"

[ -f "$MANIFEST" ] || { echo "manifest not found: $MANIFEST" >&2; exit 1; }

expand() {
    local s="$1"
    s="${s//\$DOTFILES/$DOTFILES}"
    s="${s//\$HOME/$HOME}"
    printf '%s' "$s"
}

unlink_if_ours() {
    local src="$1" dst="$2"
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        rm "$dst"
        echo "  ✗ removed $dst"
    else
        echo "  - skipped $dst (not our symlink)"
    fi
}

echo "Removing dotfile symlinks declared in $MANIFEST..."

# Reverse order so child links (e.g. ~/.claude/*) are removed before their parent (~/.agents).
# Use a Bash 3.2-compatible read loop (macOS /bin/bash) instead of mapfile.
lines=()
while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    lines+=("$line")
done < "$MANIFEST"

for (( i=${#lines[@]}-1 ; i>=0 ; i-- )); do
    IFS=$'\t' read -r src dst <<< "${lines[i]}"
    unlink_if_ours "$(expand "$src")" "$(expand "$dst")"
done

echo "Done."
