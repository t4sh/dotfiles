# AGENTS.md

Canonical agent configuration. This file is an index — edit rules in `./rules/` and they'll be composed at load time.

Symlink this file (or its expanded form) into each tool's expected location:

- Claude Code: `~/.claude/CLAUDE.md → ~/.agents/AGENTS.md`
- Cursor: paste expanded contents into User Rules, or symlink per project as `.cursor/rules/global.mdc`
- VS Code Copilot: list `rules/*.md` files in `github.copilot.chat.codeGeneration.instructions`
- Antigravity: use its rules path, or a flattened export from the agents tree

## First Steps

1. Read this file completely.
2. Read the always-on rule files, then read only the activated rule files whose trigger condition matches the current task.
   The always-on rule files are the files listed under the `## Always on` heading below.
   Do not load inactive rule files just because they exist in `~/.agents/rules/`.
3. Read `.agent-memory/index.yaml` to discover available project context. If `.agent-memory/` is absent, proceed without it — don't create it.
4. Load relevant memory files based on the current task.

---

## Always on

@./rules/00-core.md
@./rules/01-authorization.md
@./rules/02-attribution.md
@./rules/03-worktree-hygiene.md
@./rules/04-codex-host-tooling.md
@./rules/10-design-posture.md
@./rules/99-anti-patterns.md

## Activate when code is involved

Trigger signals: a package manifest (`package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, etc.), a source repo, or an explicit request to write, review, or run code.

@./rules/20-code-posture.md
@./rules/22-environment.md
@./rules/23-verification.md

## Activate when the project uses browser-rendered UI

@./rules/21-web-stack.md
@./rules/24-frontend-verification.md

## Activate when the task touches a repo with multiple runtimes, native code, generated outputs, CLI/desktop UI, bindings, or service boundaries

@./rules/25-tech-stack-discovery.md

## Activate when using Paseo agents, worktrees, loops, schedules, or daemon tooling

@./rules/05-paseo-orchestration.md

## Activate for research validation projects

@./rules/30-research-mode.md

## Activate when facts may be current or external

@./rules/31-current-info.md

---

## How to respond (applies globally)

- Lead with the change, not the explanation. Show the code or spec first, then explain only if needed.
- Skip preamble. No "Great question!" or "Sure, happy to help!" — just do the work.
- When flagging a problem, be direct: what's wrong, where, and what the fix is.
- If you're unsure, say so in one line. Don't hedge for three paragraphs.
- For design work, prefer a token map or component spec over prose descriptions of a UI.
- **Present findings as structured output, not prose.** Use tables (severity, effort, file:line), bullet lists, or fenced code blocks — not paragraphs. Output should be copy-pasteable as markdown so the user can annotate, comment, and expand directly.
