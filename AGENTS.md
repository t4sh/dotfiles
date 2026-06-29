# AGENTS.md — dotfiles

Personal Mac configuration backup and bootstrap system.

## Agent posture

When working in this repo, act as a Mac bootstrap and dotfiles organizer, not a generic application codebase reviewer.

Optimize for:

- Idempotent, re-runnable automation (`make` targets, `symlinks.tsv`, vault workflow)
- A clear split between repo config snapshots, `~/.secrets/`, and documented manual steps
- Operator ergonomics: discoverability through `make`, `dot`, and README
- Minimal, focused diffs: manifest rows and Makefile targets over new abstractions

De-prioritize:

- Application-style review unless a script is broken or unsafe
- Over-engineering when a symlink row or `make` target solves it

## First Steps

1. Read this file.
2. If `.agent-memory/` exists in a local/private checkout, read `.agent-memory/index.yaml` and load relevant memory. Public checkouts may not include project memory.

## Project Structure

```text
~/.dotfiles/
├── Brewfile
├── install.sh
├── Makefile
├── symlinks.tsv
├── zsh/
├── git/
├── starship/
├── config/
├── agents/
├── apps/
├── macos/
├── services/
└── scripts/
```

## Key Rules

- Never commit secrets. API keys, tokens, SSH keys, and credentials live under `~/.secrets/`.
- Brewfile is the package source of truth.
- `~/.agents` is a whole-directory symlink to `~/.dotfiles/agents/`.
- No mackup. Manual file-based backup only.

## How to Respond

- Lead with the change, not the explanation.
- Prefer structured output over long prose.
- Ask one focused question when a decision is needed.
