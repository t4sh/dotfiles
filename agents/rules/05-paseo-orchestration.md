# 05 - Paseo orchestration

Activate only when the task uses Paseo agents, worktrees, loops, schedules, heartbeats, provider discovery, browser tools, MCP injection, or daemon diagnostics.

## Scope

Paseo owns agent, worktree, loop, schedule, heartbeat, and daemon lifecycle state. Use Paseo tools or the `paseo` CLI for those surfaces instead of editing `~/.paseo` state files directly or substituting ad hoc git worktree management.

Generic host-tooling rules still apply to sandbox false-negatives, browser access, and GitHub auth checks, but they do not override Paseo's orchestration contract.

## Provider selection

- Before a Paseo skill chooses a provider or creates an agent, read `~/.paseo/orchestration-preferences.json` unless the user explicitly named a provider.
- If the preferences file is missing, say so once and use the Paseo skill defaults.
- Provider IDs, modes, thinking options, and feature flags must come from orchestration preferences or provider inspection. Do not hardcode new provider choices into helper skills.
- Only set provider-specific feature IDs returned by provider inspection.

## Worktrees and branches

- Paseo `create_worktree` and `create_agent.workspace.source.kind = "worktree"` are allowed lifecycle primitives for Paseo-managed agents.
- Branch names passed to Paseo must follow the repo's branch policy. Prefer workflow namespaces such as `feature/<slug>`, `bugfix/<slug>`, `hotfix/<slug>`, or `release/<version>` when the repo expects git-flow naming.
- Do not use agent/operator namespaces such as `codex/*`, `claude/*`, `cursor/*`, `gemini/*`, `ash/*`, or `tash/*`.
- Avoid generic `fix/<slug>` unless the repo explicitly uses that namespace.
- Treat the returned Paseo `branchName`, `worktreePath`, and `workspaceId` as authoritative. Do not assume they match the requested slug.
- Do not place an agent in a worktree by using `workspace: { kind: "current", cwd: "<worktreePath>" }`; use a Paseo-created or existing workspace instead.

## Agent lifecycle

- Use `relationship: { kind: "subagent" }` for advisors, committees, planners, implementers, auditors, and loop workers whose lifetime belongs to the current task.
- Use `relationship: { kind: "detached" }` for handoffs and delegations the user may continue after the current agent is archived.
- Leave `notifyOnFinish` omitted or set to `true` unless the work is truly fire-and-forget.
- Prefer asynchronous completion notifications. Do not repeatedly poll running agents just to check whether they are done.
- Archive agents only when the workflow calls for it or the user asks.

## Browser and MCP tooling

- If Paseo browser tools or MCP injection are available for a Paseo-managed agent, prefer that Paseo-provided route for that agent's browser checks before external browser fallbacks.
- If Paseo browser tooling fails because of sandbox, host access, writable state, or MCP routing, treat it as a tooling-context signal first and then use the generic host-tooling fallback rules.

## Host-native first for known sandbox-hostile tools

Inside Paseo-managed Codex agents, do not spend a first attempt on the sandboxed path for commands that are already known to need host auth, browser state, localhost reachability, writable browser state, or network access. Start with the narrow host-native, escalated, or already-approved path when the active client supports it.

Use this direct path for:

- `gh` operations, live GitHub auth checks, PR checks, workflow checks, issue/PR reads, and GitHub API commands.
- Browser verification that depends on localhost, Chrome/Chrome Canary state, Playwright browsers, `agent-browser`, or a writable browser/tool state directory.
- Playwright commands that need browser binaries, system browser access, networked installs, or a live dev server.
- Local preview checks where sandboxed `curl`, `localhost`, `127.0.0.1`, or `file://` probes are known to false-negative.

If the active host policy forbids escalation, use the available Paseo browser tools, MCP tools, connectors, plugins, or configured writable roots first, then report the routing limitation.

## Daemon safety

- Never restart or kill the Paseo daemon without explicit user approval. Restarting the daemon can interrupt every running agent, including the one asking.
- Diagnose daemon issues in this order: daemon log, `paseo daemon status`, then the health endpoint.
- Do not modify `~/.paseo/agents`, `~/.paseo/projects`, schedules, loops, PID files, or key files directly unless the user explicitly asks for low-level repair after diagnostics.
