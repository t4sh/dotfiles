# Generic Hermes preferences

Initialize and authenticate Hermes first. Merge selected JSON fragments into the
active profile's `config.yaml` (JSON is valid YAML); preserve other fields. Back up
the destination and remove the merged keys or restore that backup to undo changes.
These files are examples, not captured profiles or automatically applied settings.

| Fragment | Coverage and effect |
| --- | --- |
| [config.json](config.json) | Display/session behavior, compression, limits, manual dangerous-command approvals, memory disabled, reviewed shared skills |
| [memory-opt-in.json](memory-opt-in.json) | Explicitly enable built-in memory/profile storage with write approval; no stored content included |
| [terminal-docker.json](terminal-docker.json) | Optional Docker execution backend and empty environment forwarding lists; requires Docker |
| [SOUL.example.md](SOUL.example.md) | Original generic instructions; review before copying into your profile's SOUL.md |

The base example caps a run at 50 turns or 900 seconds: these are illustrative
operator budgets, not tuned performance recommendations. Increase/remove them for
long work. Its compression ratio starts at 75% context usage; the runtime can
adjust the effective trigger. Review compression behavior for your chosen model.
Memory is disabled in the base; enabling it stores data locally and may put saved
content into model prompts. Disabling it does not erase old memories or sessions.

An empty `create_dir` keeps skill creation profile-local. External skill discovery
is optional; review the shared skills first. Project discovery and inline skill
shell execution are disabled. Approval settings govern dangerous commands, not
every tool call, and do not create an OS sandbox. Noninteractive dangerous commands
are denied. The Docker option may download the upstream default image and run
processes; it is not a promise of network isolation or no host mounts.

Provider/model IDs and public endpoints can be documented in a separately reviewed
example; keep your selected provider/authentication in local setup. This collection
adds no model aliases, gateway IDs, remote servers, MCP tools, hooks, telemetry
identifiers, external memory providers or trusted-project inventories. The generic
instructions are newly authored and do not copy a private rulebook/persona.

Reference: [Hermes configuration](https://hermes-agent.nousresearch.com/docs/user-guide/configuration/)
and [upstream defaults](https://github.com/NousResearch/hermes-agent/blob/main/hermes_cli/config_defaults.py),
checked 2026-10-10. JSON syntax and supported key paths were checked offline;
live config loading, model calls and Docker execution remain unrun.
