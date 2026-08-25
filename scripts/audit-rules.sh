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
WORKTREE_RULE="$RULES_DIR/03-worktree-hygiene.md"
PASEO_RULE="$RULES_DIR/05-paseo-orchestration.md"
PREFLIGHT_REF="$RULES_DIR/03-worktree-hygiene/github-preflight.md"
TERMINAL_REF="$RULES_DIR/03-worktree-hygiene/terminal-integration.md"
INTEGRATION_FIXTURE="$DOTFILES/scripts/test-agent-terminal-integration.sh"

[ -f "$AGENTS_MD" ] || { echo "not found: $AGENTS_MD" >&2; exit 1; }
[ -d "$RULES_DIR" ] || { echo "not found: $RULES_DIR" >&2; exit 1; }
[ -f "$INIT_SKILL" ] || { echo "not found: $INIT_SKILL" >&2; exit 1; }
[ -f "$WORKTREE_RULE" ] || { echo "not found: $WORKTREE_RULE" >&2; exit 1; }
[ -f "$PASEO_RULE" ] || { echo "not found: $PASEO_RULE" >&2; exit 1; }
[ -f "$INTEGRATION_FIXTURE" ] || { echo "not found: $INTEGRATION_FIXTURE" >&2; exit 1; }

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
# The Markdown backticks and path are literal.
# shellcheck disable=SC2016
grep -Fq 'Discover every top-level `~/.agents/rules/*.md` file' "$AGENTS_MD" \
    || fail_contract "AGENTS.md must require exhaustive top-level rule discovery"
grep -Fq 'Loading is not applying' "$AGENTS_MD" \
    || fail_contract "AGENTS.md must distinguish loading from applying"

# The Markdown backticks and glob are literal.
# shellcheck disable=SC2016
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

grep -Fq 'git worktree list --porcelain -z' "$WORKTREE_RULE" \
    || fail_contract "worktree rule must require NUL-safe porcelain parsing"
# Integration recipes live in non-loaded references; policy stays in the rule.
[ -f "$PREFLIGHT_REF" ] || fail_contract "missing integration reference: $PREFLIGHT_REF"
[ -f "$TERMINAL_REF" ] || fail_contract "missing integration reference: $TERMINAL_REF"
grep -Fq 'rules/03-worktree-hygiene/github-preflight.md' "$WORKTREE_RULE" \
    || fail_contract "integration rule must point at its GitHub preflight reference"
grep -Fq 'rules/03-worktree-hygiene/terminal-integration.md' "$WORKTREE_RULE" \
    || fail_contract "integration rule must point at its terminal recipe"
grep -Fq 'gh api --paginate "repos/{owner}/{repo}/rules/branches/<url-encoded-pr-base>"' "$PREFLIGHT_REF" \
    || fail_contract "preflight reference must use the non-interactive applicable-rules API"
grep -Fq 'parameters.allowed_merge_methods' "$PREFLIGHT_REF" \
    || fail_contract "preflight reference must honor branch-specific merge methods"
if grep -qE '@\./rules/03-worktree-hygiene/' "$AGENTS_MD"; then
    fail_contract "integration recipes must stay references, not always-on includes"
fi
grep -Fq 'The repository owns the history shape' "$WORKTREE_RULE" \
    || fail_contract "integration rule must let repository policy select history shape"
grep -Fq '02-attribution.md` owns the identity' "$WORKTREE_RULE" \
    || fail_contract "integration rule must preserve identity through terminal Git"
grep -Fq 'git push origin <integrationOid>:refs/heads/<pr-base>' "$WORKTREE_RULE" \
    || fail_contract "integration rule must pin the verified result and live PR base"
grep -Fq 'git merge --squash <headRefOid>' "$TERMINAL_REF" \
    || fail_contract "integration rule must define the local squash method"
grep -Fq 'git merge --no-ff --no-edit [-S] -F <message-file> <headRefOid>' "$TERMINAL_REF" \
    || fail_contract "integration rule must define a non-interactive merge-commit method"
grep -Fq 'git rebase --force-rebase --onto <baseRefOid> <mergeBase>' "$TERMINAL_REF" \
    || fail_contract "integration rule must force replay for selected rebase"
if grep -Fq 'gh pr close' "$WORKTREE_RULE" || grep -Fq 'gh pr close' "$TERMINAL_REF"; then
    fail_contract "terminal integration must not simulate hosting merge with manual PR closure"
fi
# Placement contract: every newly created worktree uses the primary checkout's one canonical parent.
grep -Fq '<repo-root>/.worktrees/<full-branch-name>' "$WORKTREE_RULE" \
    || fail_contract "worktree creation must use the canonical .worktrees parent"
grep -Fq '<repo-root>/.worktrees/.integration/<PR>' "$WORKTREE_RULE" \
    || fail_contract "integration worktree must use .worktrees/.integration"
# The Markdown backticks are literal.
# shellcheck disable=SC2016
grep -Fq 'Git common directory' "$WORKTREE_RULE" \
    || fail_contract "personal worktree ignore coverage must stay in Git-local metadata"
grep -Fq 'Existing legacy worktrees elsewhere may be discovered and used in place' "$WORKTREE_RULE" \
    || fail_contract "legacy worktree placement must not become the creation convention"
grep -Fq '<repo-root>/.worktrees/<full-branch-name>' "$PASEO_RULE" \
    || fail_contract "Paseo worktrees must use the canonical .worktrees parent"
# The shell variables are literal fixture source text.
# shellcheck disable=SC2016
grep -Fq 'worktree_parent="$main_worktree/.worktrees"' "$INTEGRATION_FIXTURE" \
    || fail_contract "integration fixture must exercise the canonical .worktrees parent"
if grep -Fq '.git/agent-integration' "$WORKTREE_RULE" "$TERMINAL_REF"; then
    fail_contract "integration worktrees must not live inside Git metadata"
fi
if grep -Fq 'git flow init' "$WORKTREE_RULE"; then
    fail_contract "global rules must not initialize repository workflow policy"
fi
grep -Fq 'git commit --only -- <path>…' "$WORKTREE_RULE" \
    || fail_contract "scoped commits must guard against unstaged target-path content"
# The Markdown backticks are literal.
# shellcheck disable=SC2016
grep -Fq 'workflow that depends on a hosting `MERGED` event' "$WORKTREE_RULE" \
    || fail_contract "integration rule must expose hosting-only semantics"
grep -Fq 'Do not comment on or close the PR without separate authorization.' "$WORKTREE_RULE" \
    || fail_contract "terminal integration must keep remote PR actions separately authorized"

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
    bash "$DOTFILES/scripts/test-agent-terminal-integration.sh"
fi

exit "$status"
