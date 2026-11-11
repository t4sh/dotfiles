#!/usr/bin/env bash
# Report filesystem bridge placement separately from actual instruction delivery.
set -euo pipefail
root="${DOTFILES:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
status=0
check_bridge() {
  local label="$1" path="$2" expected="$3"
  if [[ -L "$path" && -f "$expected" && "$(readlink "$path")" == "$expected" ]] && cmp -s "$path" "$expected"; then
    printf '%s: bridge file matches; fresh-session behavior not established by this check\n' "$label"
  else
    printf '%s: bridge missing or drifted; run make link\n' "$label"
    status=1
  fi
}
check_bridge Codex "$HOME/.codex/AGENTS.md" "$root/config/codex/AGENTS.md"
check_bridge 'Claude Code' "$HOME/.claude/CLAUDE.md" "$root/agents/AGENTS.md"
check_bridge 'Zed native agent' "$HOME/.config/zed/AGENTS.md" "$root/config/zed/AGENTS.md"
check_bridge OpenCode "$HOME/.config/opencode/AGENTS.md" "$root/config/opencode/AGENTS.md"
check_bridge Cursor "$HOME/.cursor/rules/rulebook.mdc" "$root/config/cursor/rulebook.mdc"
check_bridge 'VS Code Copilot harness' "$HOME/.copilot/copilot-instructions.md" "$root/config/copilot/copilot-instructions.md"
check_bridge Antigravity "$HOME/.gemini/GEMINI.md" "$root/config/antigravity/GEMINI.md"
printf '%s\n' 'See agents/CLIENTS.md for runtime evidence and harness limits. Skill links and MCP connectivity are separate from instruction delivery.'
exit "$status"
