#!/usr/bin/env bash
# Windows uses native entry points; reject before any Unix-path mutation.
case "${OS:-}:$(uname -s)" in
  Windows_NT:*|*:MINGW*|*:MSYS*) echo 'This is a macOS workflow. On Windows run bin/dot.cmd help.' >&2; exit 2 ;;
esac
# Apply symlinks declared in symlinks.tsv. Idempotent — re-run safe.
# Missing sources leave destinations untouched. Existing destinations for valid
# sources move to ~/.dotfiles-backup/<timestamp>/<absolute-path-mirror>.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
MANIFEST="$DOTFILES/symlinks.tsv"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
DRY_RUN=0
CHECK=0
MISSING_SOURCES=0
DRIFTED_DESTINATIONS=0

usage() {
    cat <<'EOF'
Usage: link.sh [--dry-run | --check]

  --dry-run   Show what would be linked/backed up without changing files.
  --check     Exit non-zero when a source is missing or a destination has drifted.

Environment:
  DOTFILES_STRICT_LINK=1   Exit non-zero when any declared source is missing
                           (normal apply mode; --check already fails on missing sources).
EOF
}

while (($# > 0)); do
    case "$1" in
        -n | --dry-run)
            DRY_RUN=1
            shift
            ;;
        -c | --check)
            DRY_RUN=1
            CHECK=1
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
bash "$DOTFILES/scripts/validate-manifests.sh" symlinks

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

candidate_path_for() {
    local dst="$1" dir base candidate n
    dir="$(dirname "$dst")"
    base="$(basename "$dst")"
    candidate="$dir/.$base.dotfiles-link.$$"
    if [[ ! -e "$candidate" && ! -L "$candidate" ]]; then
        printf '%s' "$candidate"
        return
    fi

    n=1
    while [[ -e "$candidate.$n" || -L "$candidate.$n" ]]; do
        n=$((n + 1))
    done
    printf '%s' "$candidate.$n"
}

link_one() {
    local src="$1" dst="$2" backup="" candidate status
    if [[ ! -e "$src" ]]; then
        echo "  ⚠ source missing for $dst: $src"
        MISSING_SOURCES=$((MISSING_SOURCES + 1))
        echo "    leaving the destination untouched; restore the source and re-run"
        return
    fi
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        echo "  ✓ $dst (already linked)"
        return
    fi

    DRIFTED_DESTINATIONS=$((DRIFTED_DESTINATIONS + 1))
    if (( CHECK )); then
        echo "  ✗ $dst (expected link to $src)"
        return
    fi
    if (( DRY_RUN )); then
        if [ -e "$dst" ] || [ -L "$dst" ]; then
            backup="$(backup_path_for "$dst")"
            echo "  → backing up $dst → $backup"
        fi
        echo "  + would link $dst → $src"
        return
    fi

    mkdir -p "$(dirname "$dst")"
    candidate="$(candidate_path_for "$dst")"
    if ln -s "$src" "$candidate"; then
        :
    else
        status=$?
        rm -f -- "$candidate"
        echo "  ✗ could not stage link for $dst" >&2
        return "$status"
    fi

    if [ -e "$dst" ] || [ -L "$dst" ]; then
        backup="$(backup_path_for "$dst")"
        echo "  → backing up $dst → $backup"
        mkdir -p "$(dirname "$backup")"
        if mv "$dst" "$backup"; then
            :
        else
            status=$?
            rm -f -- "$candidate"
            echo "  ✗ could not back up $dst" >&2
            return "$status"
        fi
    fi

    if mv "$candidate" "$dst"; then
        :
    else
        status=$?
        rm -f -- "$candidate"
        if [[ -n "$backup" && ( -e "$backup" || -L "$backup" ) ]]; then
            if mv "$backup" "$dst"; then
                :
            else
                echo "  ✗ publish failed and rollback could not restore $dst; original remains at $backup" >&2
                return "$status"
            fi
        fi
        echo "  ✗ could not publish link for $dst; previous destination restored" >&2
        return "$status"
    fi
    echo "  ✓ $dst → $src"
}

if (( CHECK )); then
    echo "Checking managed links from $MANIFEST..."
elif (( DRY_RUN )); then
    echo "Dry-run: linking dotfiles from $MANIFEST..."
else
    echo "Linking dotfiles from $MANIFEST..."
fi

# Snapshot the manifest once. In strict apply mode, validate every source before
# changing any destination so a nonzero result never means "partially applied."
MANIFEST_SOURCES=()
MANIFEST_DESTINATIONS=()
while IFS=$'\t' read -r src dst; do
    [ -z "${src:-}" ] && continue
    [[ "$src" =~ ^[[:space:]]*# ]] && continue
    MANIFEST_SOURCES+=("$(expand "$src")")
    MANIFEST_DESTINATIONS+=("$(expand "$dst")")
done < "$MANIFEST"

if [[ "${DOTFILES_STRICT_LINK:-0}" == "1" ]] && (( ! CHECK )); then
    for src in "${MANIFEST_SOURCES[@]}"; do
        if [[ ! -e "$src" ]]; then
            echo "  ⚠ strict preflight source missing: $src"
            MISSING_SOURCES=$((MISSING_SOURCES + 1))
        fi
    done
    if (( MISSING_SOURCES > 0 )); then
        echo "Strict link failed before applying changes: $MISSING_SOURCES missing source(s)."
        exit 1
    fi
fi

for i in "${!MANIFEST_SOURCES[@]}"; do
    link_one "${MANIFEST_SOURCES[$i]}" "${MANIFEST_DESTINATIONS[$i]}"
done

echo ""
if (( MISSING_SOURCES > 0 )); then
    printf '\033[1m⚠ %d declared source(s) missing — destinations left untouched.\033[0m\n' "$MISSING_SOURCES"
    echo "  Most often these are vault-backed paths under ~/.secrets/."
    echo "  Restore the vault, then re-run: make link"
    echo "  Strict mode: DOTFILES_STRICT_LINK=1 make link  # nonzero exit when any source is missing"
    echo ""
fi
if (( CHECK )); then
    if (( MISSING_SOURCES > 0 || DRIFTED_DESTINATIONS > 0 )); then
        echo "Check failed: $MISSING_SOURCES missing source(s), $DRIFTED_DESTINATIONS drifted destination(s)."
        exit 1
    fi
    echo "Check complete. All managed links are healthy."
elif (( MISSING_SOURCES > 0 )) && [[ "${DOTFILES_STRICT_LINK:-0}" == "1" ]]; then
    echo "Strict link failed: $MISSING_SOURCES missing source(s) (DOTFILES_STRICT_LINK=1)."
    exit 1
elif (( DRY_RUN )); then
    echo "Dry-run complete. No files changed."
elif [ -d "$BACKUP_DIR" ]; then
    echo "Done. Backups in $BACKUP_DIR"
else
    echo "Done. No backups needed."
fi
