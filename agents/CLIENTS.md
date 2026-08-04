# Agent client projections

`AGENTS.md` and the top-level `rules/*.md` files are the canonical rulebook. Client projections are delivery mechanisms only; they do not own membership or applicability.

| Client | Ownership | Bootstrap / refresh | Verification |
|---|---|---|---|
| Generic `~/.agents` consumers | Manifest-managed | `make link` installs the whole `agents/` directory at `~/.agents` | `bash scripts/link.sh --check` |
| Claude Code | Manifest-managed compatibility links | `make link` installs `~/.claude/CLAUDE.md`, `skills`, `agents`, and `commands` from the canonical tree | `bash scripts/link.sh --check` |
| Codex | Manifest-managed bootstrap bridge | `make link` installs `config/codex/AGENTS.md` at `~/.codex/AGENTS.md`; the bridge invokes `init-rulebook` and retains optional local `RTK.md` guidance | `bash scripts/link.sh --check`; confirm a new task loads the canonical rulebook |
| Cursor skills | Manifest-managed compatibility link | `make link` installs `~/.cursor/skills` from the canonical skills tree | `bash scripts/link.sh --check` |
| Cursor rules | Manual / vendor settings | Paste an expanded rulebook into User Rules, or add a project `.cursor/rules/global.mdc` that points at the canonical rulebook | After any rule change, inspect Cursor User Rules or the project rule and confirm the load-all/apply-conditionally contract is current |
| VS Code Copilot | Manual / vendor settings | Configure `github.copilot.chat.codeGeneration.instructions` with every top-level `~/.agents/rules/*.md` file; do not copy an inventory into `init-rulebook` | Compare the configured instruction paths with `find ~/.agents/rules -maxdepth 1 -name '*.md' | sort` |
| Antigravity | Manual / vendor settings | Use the client's supported rules path or deliberately create a flattened export from `AGENTS.md` plus all sorted top-level rules | Refresh after rule changes and confirm conditional rules are present but remain conditionally applicable |
| Nimbalyst | Host-managed | No stable repository-owned projection path is declared; the host may consume `~/.agents` | Confirm the active task exposes the current rulebook before relying on Nimbalyst-specific rules |

Generic consumers, Claude compatibility links, the Codex bootstrap bridge, and Cursor skills are automated because their filesystem paths are stable and owned by `symlinks.tsv`. Manual rule surfaces must not be reported as restored by `make link` or `make doctor`.
