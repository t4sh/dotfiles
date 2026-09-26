# AGENTS.md

Canonical agent configuration. This file is an index — edit rules in `./rules/` and they'll be composed at load time. Client projection ownership, bootstrap steps, and verification boundaries are documented in [`CLIENTS.md`](./CLIENTS.md); that document is not a rule inventory or loader input.

## First Steps

1. Read this file completely.
2. Discover every top-level `~/.agents/rules/*.md` file and compare that inventory with the rule links below. Numeric prefixes establish the intended order.
3. Read every rule under **Always on** completely. Before acting on the current request, read each task-conditional rule whose section trigger matches the task or environment.
4. Do not preload an **Action-gated** rule merely because the request mentions a later operation. Read it completely immediately before the first matching action, then keep it active for the rest of the current uncompacted context.
5. Re-evaluate task-conditional sections before later requests and action gates before later operations when scope changes.
6. Loading is not applying: honor each loaded rule only according to the applicability declared in the rule file and the section headings below.
7. Read `.agent-memory/index.yaml` to discover available project context. If `.agent-memory/` is absent, proceed without it — don't create it.
8. Load relevant memory files based on the current task.

---

The headings below declare applicability and index every rule. Rule membership is the exact match between these links and the top-level Markdown files on disk. Links are deliberately not automatic `@` includes: clients load the applicable files through `init-rulebook` instead of eagerly expanding the complete rulebook.

## Always on

- [Core principles](./rules/00-core.md)
- [Action vs proposal authorization](./rules/01-authorization.md)
- [Worktree hygiene](./rules/03-worktree-hygiene.md)
- [Design posture](./rules/10-design-posture.md)
- [Skill routing](./rules/11-skill-routing.md)
- [Anti-patterns](./rules/99-anti-patterns.md)

## Action-gated: load immediately before commit-producing, attribution, or integration work

Action signals: beginning the commit/integration workflow; preparing or finalizing a commit message; running a commit-producing command; cherry-picking, reverting, merging, or rebasing; publishing a commit; or verifying Git author/committer identity or signing. A request that merely schedules one of these after earlier implementation work does not open the gate yet.

- [Commit attribution](./rules/02-attribution.md)

## Action-gated: load immediately before worktree creation, branch creation, finishing, merge, or cleanup

Action signals: creating a git worktree; creating a branch for isolation; finishing development work; merging a pull request; post-merge or stale-branch cleanup; or producing a handoff after branch/PR/merge/cleanup work. Daily checkout safety stays in the always-on worktree hygiene rule.

- [Worktree lifecycle](./rules/07-worktree-lifecycle.md)

## Activate for host-authenticated, browser, localhost, or sandbox-sensitive tooling

Trigger signals: GitHub CLI or API work, browser verification, localhost previews, Playwright or browser processes, host authentication, network access, or an unexpected sandbox/permission false-negative.

- [Codex host tooling](./rules/04-codex-host-tooling.md)

## Activate when code is involved

Trigger signals: a package manifest (`package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, etc.), a source repo, or an explicit request to write, review, or run code.

- [Code posture](./rules/20-code-posture.md)
- [Environment and package managers](./rules/22-environment.md)
- [Verification before completion](./rules/23-verification.md)

## Activate when the project uses browser-rendered UI

- [Web stack rules](./rules/21-web-stack.md)
- [Frontend verification](./rules/24-frontend-verification.md)

## Activate when the task touches a repo with multiple runtimes, native code, generated outputs, CLI/desktop UI, bindings, or service boundaries

- [Tech stack discovery](./rules/25-tech-stack-discovery.md)

## Activate when using Paseo agents, worktrees, loops, schedules, or daemon tooling

- [Paseo orchestration](./rules/05-paseo-orchestration.md)

## Activate when Hermes captures learning or performs skill maintenance

- [Hermes learning](./rules/06-hermes-learning.md)

## Activate for research validation projects

- [Research mode](./rules/30-research-mode.md)

## Activate when facts may be current or external

- [Current information](./rules/31-current-info.md)

---

## How to respond (applies globally)

- Lead with the change, not the explanation. Show the code or spec first, then explain only if needed.
- Skip preamble. No "Great question!" or "Sure, happy to help!" — just do the work.
- When flagging a problem, be direct: what's wrong, where, and what the fix is.
- If you're unsure, say so in one line. Don't hedge for three paragraphs.
- For design work, lead with the selected mode's required artifact. Use a token map or component contract when that artifact calls for one; do not reduce UX architecture or research work to styling prose.
- For interface work, lead with the design outcome and rendered quality. Keep repository and Git housekeeping out of the response unless it blocks the work or the user asks for it.
- **Present findings as structured output, not prose.** Use tables (severity, effort, file:line), bullet lists, or fenced code blocks — not paragraphs. Output should be copy-pasteable as markdown so the user can annotate, comment, and expand directly.
- **Don't pad.** Length is not weight: no restated context, no filler sections, no scope recap to make a short answer feel substantial. A clean result stated in one line is complete — once the probes behind it are actually finished, and it says which ones they were.
