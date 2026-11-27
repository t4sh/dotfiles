# Generic Codex preferences

Merge [config.toml](config.toml) into user `~/.codex/config.toml`, preserving other
settings. No file here is installed or discovered as live configuration by the
bootstrap. Back up the destination first; remove added keys/sections or restore
the backup to undo changes. Authenticate through your installed client's login.

The fragment covers approval, workspace/network policy, web search, reasoning display, citation opening, shell environment inheritance, history
and TUI notifications/input. Approval on request is not a prompt for every action.
Host/organization policy can constrain the settings; do not interpret these values
as a complete security boundary. Core environment inheritance and secret-name
exclusions can require explicit local tool setup. History persistence controls
`history.jsonl`; it does not disable every session store, log or remote retention.

The current CLI uses named config layer files. To opt in, place
[review.config.toml](review.config.toml) or [edit.config.toml](edit.config.toml)
next to your user config, keeping those filenames, and select `codex --profile
review` or `codex --profile edit`. Use your configured CODEX_HOME when customized.
Review mode is read-only; edit mode allows workspace writes with sandbox network
disabled. Both disable web search and retain approval requests. They select
permissions, not a model/provider. Existing settings and host policy still apply.
Older clients can differ: check their CLI help before copying a named layer.

[AGENTS.example.md](AGENTS.example.md) is original generic project guidance. Review
it before merging into a project's actual AGENTS.md; its example filename avoids
automatic activation. Model/provider choice, reasoning effort, MCP servers, hooks,
project trust and credentials stay in local setup. Reasoning display support
varies by model; TUI preferences do not imply desktop UI equivalence.

References: [Codex CLI profiles](https://learn.chatgpt.com/docs/cli/reference) and
[OpenAI configuration reference](https://developers.openai.com/codex/config-reference/),
checked 2026-10-10. TOML syntax and documented keys were checked; live client
loading, authentication and actual permission enforcement remain unrun.
