# 04 — Codex host tooling

Always on. These rules prevent sandbox and browser-tooling false negatives from being treated as real project state.

## Sandbox false-negatives

When a useful terminal, GitHub CLI, browser, MCP, localhost, network, or script command fails because of sandboxing, host auth isolation, filesystem permissions, missing writable state, or restricted network access:

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
- If localhost probes fail in the sandbox, verify through the host/browser path before declaring the preview down or starting another server.

## Generated report locations

For Codex-generated reports, audits, screenshots indexes, HTML summaries, and similar temporary review artifacts:

- Prefer `/private/tmp/<app>-reports/` as the default output directory, where `<app>` is the repo, product, or task slug such as `neo`, `lab-sites`, or `dotfiles`.
- Keep generated reports outside the source repo unless the user explicitly asks to commit or preserve the artifact with the project.
- Use a skill-specified, project-specified, or user-specified path when one is given, but favor the stable app report directory when instructions only say "temp" or leave the location open.
- Include the final absolute path in the handoff so the report can be reopened without searching through per-session macOS temp folders.

## Decision shape

Use trigger/behavior/fallback thinking for repeat failures:

- Trigger: sandboxed `gh` says unavailable or unauthenticated.
- Behavior: retry via host-provided GitHub tooling or native/host `gh`, using the narrowest available approved path.
- Fallback: only report auth unavailable after native `gh` fails too.

- Trigger: localhost or browser automation cannot reach a preview from the sandbox.
- Behavior: in Nimbalyst, verify local targets with the Nimbalyst Browser plugin / in-app browser; outside Nimbalyst, verify with the configured real browser path, preferably Chrome Canary.
- Fallback: ask the user to restore the expected preview only after the host/browser path also fails.
