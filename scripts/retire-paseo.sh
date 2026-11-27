#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Preview or retire the six former dotfiles-owned Paseo skill links.

Usage: scripts/retire-paseo.sh [--apply]

Preview is the default. --apply removes only exact symlinks into this checkout's
former agents/skills/paseo* directories. It never removes app data or directories.
EOF
}

retire_paseo() {
    local apply=0 arg repo home codex skills name target expected actual found=0
    case "$(uname -s)" in
        Darwin) ;;
        *) printf 'This helper is for macOS; no links changed.\n' >&2; return 1 ;;
    esac
    for arg in "$@"; do
        case "$arg" in
            --apply) apply=1 ;;
            -h|--help) usage; return 0 ;;
            *) printf 'Unknown argument: %s\n' "$arg" >&2; usage >&2; return 2 ;;
        esac
    done

    repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
    home=${HOME:?HOME must be set}
    codex="$home/.codex"
    skills="$codex/skills"

    # Never traverse a foreign junction/symlink while inspecting or unlinking.
    if [[ -L "$codex" || -L "$skills" ]]; then
        printf 'Refusing Paseo cleanup: %s or %s is a symlink. Review it manually.\n' "$codex" "$skills" >&2
        return 1
    fi
    if [[ ! -d "$skills" ]]; then
        printf 'No Codex skills directory at %s; nothing to retire.\n' "$skills"
        return 0
    fi

    for name in paseo paseo-advisor paseo-committee paseo-handoff paseo-help paseo-plugin; do
        target="$skills/$name"
        expected="$repo/agents/skills/$name"
        [[ -L "$target" ]] || continue
        actual=$(readlink "$target")
        if [[ "$actual" != "$expected" ]]; then
            printf 'Preserving foreign symlink: %s -> %s\n' "$target" "$actual"
            continue
        fi
        found=1
        if (( apply )); then
            rm -- "$target"
            printf 'Removed owned link: %s\n' "$target"
        else
            printf 'Would remove owned link: %s -> %s\n' "$target" "$expected"
        fi
    done
    if (( ! found )); then printf 'No exact former Paseo links found; nothing to retire.\n'; fi
    if (( ! apply )); then printf 'Preview only. Re-run with --apply to remove listed links.\n'; fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    retire_paseo "$@"
fi
