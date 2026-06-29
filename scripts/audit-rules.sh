#!/usr/bin/env bash
# Rulebook drift guard. Asserts a 1:1 match between the `@./rules/*.md` includes
# in agents/AGENTS.md and the actual agents/rules/*.md files on disk.
#
#   missing — referenced in AGENTS.md but not on disk
#   orphan  — on disk but not referenced in AGENTS.md
#
# Exits non-zero on any mismatch. Wired via `make rules-audit`.
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
AGENTS_MD="$DOTFILES/agents/AGENTS.md"
RULES_DIR="$DOTFILES/agents/rules"

[ -f "$AGENTS_MD" ] || { echo "not found: $AGENTS_MD" >&2; exit 1; }
[ -d "$RULES_DIR" ] || { echo "not found: $RULES_DIR" >&2; exit 1; }

# Referenced: basenames pulled from `@./rules/<name>.md` lines, sorted.
referenced="$(grep -oE '@\./rules/[A-Za-z0-9._-]+\.md' "$AGENTS_MD" \
    | sed 's#@\./rules/##' | sort -u)"

# On disk: basenames of agents/rules/*.md, sorted.
on_disk="$(find "$RULES_DIR" -maxdepth 1 -type f -name '*.md' -exec basename {} \; | sort -u)"

missing="$(comm -23 <(printf '%s\n' "$referenced") <(printf '%s\n' "$on_disk"))"
orphan="$(comm -13 <(printf '%s\n' "$referenced") <(printf '%s\n' "$on_disk"))"

status=0
if [ -n "$missing" ]; then
    printf '\033[31m✗ referenced in AGENTS.md but missing on disk:\033[0m\n' >&2
    printf '%s\n' "$missing" | sed 's/^/    /' >&2
    status=1
fi
if [ -n "$orphan" ]; then
    printf '\033[31m✗ on disk but not referenced in AGENTS.md:\033[0m\n' >&2
    printf '%s\n' "$orphan" | sed 's/^/    /' >&2
    status=1
fi

if [ "$status" -eq 0 ]; then
    count="$(printf '%s\n' "$on_disk" | grep -c .)"
    printf '\033[32m  ✓\033[0m rulebook in sync (%s rules)\n' "$count"
fi

exit "$status"
