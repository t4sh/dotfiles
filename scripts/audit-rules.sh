#!/usr/bin/env bash
# Rulebook drift guard. Asserts a 1:1 match between the `@./rules/*.md` includes
# in agents/AGENTS.md and the actual agents/rules/*.md files on disk.
#
#   missing — referenced in AGENTS.md but not on disk
#   orphan  — on disk but not referenced in AGENTS.md
#
# Exits non-zero on any mismatch. Wired via `make rules-audit`.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
AGENTS_MD="$DOTFILES/agents/AGENTS.md"
RULES_DIR="$DOTFILES/agents/rules"
INIT_SKILL="$DOTFILES/agents/skills/init-rulebook/SKILL.md"

[ -f "$AGENTS_MD" ] || { echo "not found: $AGENTS_MD" >&2; exit 1; }
[ -d "$RULES_DIR" ] || { echo "not found: $RULES_DIR" >&2; exit 1; }
[ -f "$INIT_SKILL" ] || { echo "not found: $INIT_SKILL" >&2; exit 1; }

# Referenced: basenames pulled from `@./rules/<name>.md` lines, sorted.
referenced="$(grep -oE '@\./rules/[A-Za-z0-9._-]+\.md' "$AGENTS_MD" \
    | sed 's#@\./rules/##' | sort -u)"

# On disk: basenames of agents/rules/*.md, sorted.
on_disk="$(/usr/bin/find "$RULES_DIR" -maxdepth 1 -type f -name '*.md' -exec basename {} \; | sort -u)"

missing="$(comm -23 <(printf '%s\n' "$referenced") <(printf '%s\n' "$on_disk"))"
orphan="$(comm -13 <(printf '%s\n' "$referenced") <(printf '%s\n' "$on_disk"))"

status=0
fail_contract() {
    printf '\033[31m✗ rulebook contract: %s\033[0m\n' "$1" >&2
    status=1
}

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

# Loading mechanics belong to init-rulebook; membership and applicability do not.
grep -Fq 'Discover every top-level `~/.agents/rules/*.md` file' "$AGENTS_MD" \
    || fail_contract "AGENTS.md must require exhaustive top-level rule discovery"
grep -Fq 'Loading is not applying' "$AGENTS_MD" \
    || fail_contract "AGENTS.md must distinguish loading from applying"

grep -Fq 'enumerate every top-level `*.md` file' "$INIT_SKILL" \
    || fail_contract "init-rulebook must discover every top-level rule from disk"
grep -Fq 'successfully read count' "$INIT_SKILL" \
    || fail_contract "init-rulebook must compare discovered and successfully read counts"
grep -Fq 'unreadable file or failed read as an error' "$INIT_SKILL" \
    || fail_contract "init-rulebook must fail closed on unreadable rules"
grep -Fq 'loading a rule is distinct from applying it' "$INIT_SKILL" \
    || fail_contract "init-rulebook must defer applicability to the rulebook"

if grep -Fq '@./rules/' "$INIT_SKILL"; then
    fail_contract "init-rulebook must not use index includes as its inventory"
fi

while IFS= read -r rule; do
    [ -n "$rule" ] || continue
    if grep -Fq "$rule" "$INIT_SKILL"; then
        fail_contract "init-rulebook contains static rule filename: $rule"
    fi
    if ! sed -n '2,5p' "$RULES_DIR/$rule" | grep -Eq 'Always on\.|^Activate |^Never do'; then
        fail_contract "$rule does not declare applicability near the top"
    fi
done <<< "$on_disk"

if [ "$status" -eq 0 ]; then
    count="$(printf '%s\n' "$on_disk" | grep -c .)"
    printf '\033[32m  ✓\033[0m rulebook in sync (%s rules)\n' "$count"
fi

exit "$status"
