# 04 — Codex host tooling

Always on. These rules prevent sandbox and browser-tooling false negatives from being treated as real project state.

## Host-native first for known sandbox-hostile operations

Do not spend a first attempt on the sandboxed path when the operation is already known to require host authentication, host browser state, localhost reachability, writable browser state, restricted network access, or Git metadata writes. Classify the operation before running it, then start with the narrowest host-native, escalated, plugin-provided, or already-approved path supported by the active client.

Use this direct path for:

- `gh` operations, live GitHub authentication checks, PR and workflow checks, issue or PR reads, and GitHub API commands.
- Git commands that write metadata when the active sandbox exposes `.git` read-only or the command already has a narrow persisted approval. Read-only commands such as `git status`, `git diff`, and `git log` may remain sandboxed when they work there.
- Browser verification that depends on host `localhost`, Chrome or Chrome Canary state, Playwright browser processes, `agent-browser`, or a writable browser profile or state directory.
- Playwright commands that need browser binaries, macOS browser process services, live localhost access, networked installs, or another known host-only capability.
- Local preview checks where sandboxed `curl`, `localhost`, `127.0.0.1`, `::1`, or `file://` probes are known to false-negative. When the user says the preview is already running, do not use a sandboxed probe to rediscover this boundary and do not start a replacement server before the host/browser path also fails.
- Repository verification wrappers such as `verify`, `test`, or `check:*` when their transitive command graph starts a local server, binds `localhost`, `127.0.0.1`, or `::1`, or launches a browser. Classify the entire wrapper by its most sandbox-hostile child and run it host-native first. Do not run most of the suite sandboxed only to repeat the whole wrapper after the known child fails.

A first sandbox attempt is appropriate only when the target's locality or permission requirement is genuinely unknown and the command is otherwise expected to work in the sandbox. When a wrapper command's requirements are not obvious, inspect its package script and referenced scripts before execution. Escalate first only when that inspection proves a host-only requirement; do not treat every `verify` or `test` command as host-only. Do not run a sacrificial command merely to justify escalation. If the active host policy forbids escalation, use the available browser tools, MCP tools, connectors, plugins, or configured writable roots first, then report the routing limitation.

## Sandbox false-negatives

When a useful terminal, GitHub CLI, browser, MCP, localhost, network, or script command fails because of sandboxing, host auth isolation, filesystem permissions, missing writable state, or restricted network access:

This section is recovery guidance for genuinely unexpected failures. It does not authorize a sandbox probe before a known host-native operation.

- Treat the first failure as a tooling-context signal, not as the authoritative project state.
- Retry with the narrowest escalated, host-native, or already-approved command path available.
- Do not report "blocked by sandbox" until the escalated/native path has also failed, approval was denied, or the operation is unsafe without explicit user input.
- For GitHub operations and live auth checks, prefer native/host `gh` as the source of truth over sandboxed `gh` output.
- If a command is important and likely failed because of sandbox or network restrictions, immediately request the narrow escalation instead of stopping to describe the sandbox failure.

## Nimbalyst exceptions

When running inside Nimbalyst, apply the same false-negative posture, but respect the active Nimbalyst host policy:

- If the active Nimbalyst policy forbids escalation, do not request `sandbox_permissions` or present escalation approval as the next step.
- Before reporting a sandbox limitation, try the provided MCP tools, connectors, plugins, configured writable roots, and `/private/tmp` when they fit the task.
- For GitHub operations and live auth checks, prefer host-provided GitHub tooling and native/host `gh` over sandboxed `gh` output.
- Treat a Nimbalyst sandbox denial as a routing constraint, not as proof that the repo, preview, auth, or service is broken.

## Browser selection

For local UI verification, visual inspection, and localhost preview checks:

- Prefer the already-configured real browser path first when a real render is needed.
- In Nimbalyst, for local web targets such as `localhost`, `127.0.0.1`, `::1`, and `file://`, prefer the Nimbalyst Browser plugin / in-app browser.
- In Nimbalyst, use Chrome or Chrome Canary only when the task depends on the user's existing Chrome state: logged-in sessions, cookies, extensions, or explicit Chrome plugin use.
- Outside Nimbalyst, use Google Chrome Canary when launching a real browser is appropriate.
- Do not try Playwright, MCP browser tools, dependency installs, or ad hoc browser scripts before using the real browser unless the task specifically requires headless automation or a repo already provides that exact script.
- If browser tooling needs writable state or host access, request the narrow escalation instead of declaring the browser unavailable.
- For known localhost targets, start with the host/browser path. Use a sandboxed probe only when the target's locality was genuinely unknown.

## Browser session lifecycle

- Reuse one task-owned browser session for the full verification pass. Change routes and viewport sizes within that session instead of launching a new browser for each check.
- Before creating a replacement automation session, close the previous task-owned session when it is no longer useful.
- At completion, interruption, or handoff, close all automation browser sessions created by the current task unless continued monitoring was requested.
- Never close the user's existing browser windows or sessions owned by another task.
- Use the Chrome control integration when verification requires the user's existing Chrome profile, cookies, extensions, or authenticated state. Playwright may use a separate isolated profile and must not be assumed capable of attaching to an ordinary running Chrome instance.

## Generated report locations

For Codex-generated reports, audits, screenshots indexes, HTML summaries, and similar temporary review artifacts:

- Prefer `/private/tmp/<app>-reports/` as the default output directory, where `<app>` is the repo, product, or task slug such as `neo`, `lab-sites`, or `dotfiles`.
- Keep generated reports outside the source repo unless the user explicitly asks to commit or preserve the artifact with the project.
- Use a skill-specified, project-specified, or user-specified path when one is given, but favor the stable app report directory when instructions only say "temp" or leave the location open.
- Include the final absolute path in the handoff so the report can be reopened without searching through per-session macOS temp folders.

## Decision shape

Use trigger/behavior/fallback thinking for repeat failures:

- Trigger: an operation requires live GitHub authentication or current repository, pull request, issue, or workflow state.
- Behavior: use host-provided GitHub tooling or native/host `gh` first, through the narrowest available approved path.
- Fallback: only report auth unavailable after native `gh` fails too.

- Trigger: verification targets `localhost`, `127.0.0.1`, `::1`, or another host-local preview.
- Behavior: in Nimbalyst, start with the Nimbalyst Browser plugin / in-app browser; outside Nimbalyst, start with the configured real browser path, preferably Chrome Canary.
- Fallback: ask the user to restore the expected preview only after the host/browser path also fails.
