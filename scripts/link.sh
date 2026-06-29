#!/usr/bin/env bash
# Apply symlinks declared in symlinks.tsv. Idempotent — re-run safe.
# Existing non-matching files are moved to ~/.dotfiles-backup/<timestamp>/<absolute-path-mirror>.
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
MANIFEST="$DOTFILES/symlinks.tsv"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
DRY_RUN=0

usage() {
    cat <<'EOF'
Usage: link.sh [--dry-run]

  --dry-run   Show what would be linked/backed up without changing files.
EOF
}

while (($# > 0)); do
    case "$1" in
        -n | --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h | --help | help)
            usage
            exit 0
            ;;
        *)
            echo "unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

[ -f "$MANIFEST" ] || { echo "manifest not found: $MANIFEST" >&2; exit 1; }

expand() {
    local s="$1"
    s="${s//\$DOTFILES/$DOTFILES}"
    s="${s//\$HOME/$HOME}"
    printf '%s' "$s"
}

backup_path_for() {
    local dst="$1"
    local rel backup n
    rel="${dst#/}"
    backup="$BACKUP_DIR/$rel"
    if [[ ! -e "$backup" && ! -L "$backup" ]]; then
        printf '%s' "$backup"
        return
    fi

    n=1
    while [[ -e "$backup.$n" || -L "$backup.$n" ]]; do
        n=$((n + 1))
    done
    printf '%s' "$backup.$n"
}

link_one() {
    local src="$1" dst="$2" backup
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        echo "  ✓ $dst (already linked)"
        return
    fi
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        backup="$(backup_path_for "$dst")"
        echo "  → backing up $dst → $backup"
        if (( ! DRY_RUN )); then
            mkdir -p "$(dirname "$backup")"
            mv "$dst" "$backup"
        fi
    fi
    if (( DRY_RUN )); then
        echo "  + would link $dst → $src"
        return
    fi
    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
    echo "  ✓ $dst → $src"
}

if (( DRY_RUN )); then
    echo "Dry-run: linking dotfiles from $MANIFEST..."
else
    echo "Linking dotfiles from $MANIFEST..."
fi

while IFS=$'\t' read -r src dst; do
    [ -z "${src:-}" ] && continue
    [[ "$src" =~ ^[[:space:]]*# ]] && continue
    link_one "$(expand "$src")" "$(expand "$dst")"
done < "$MANIFEST"

echo ""
if (( DRY_RUN )); then
    echo "Dry-run complete. No files changed."
elif [ -d "$BACKUP_DIR" ]; then
    echo "Done. Backups in $BACKUP_DIR"
else
    echo "Done. No backups needed."
fi
