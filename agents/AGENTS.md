# AGENTS.md

Canonical agent configuration. Edit rules in `./rules/`; this index controls loading. [`CLIENTS.md`](./CLIENTS.md) documents client ownership and verification; it is not a rule inventory or loader input.

## First Steps

1. Read this file completely.
2. Discover every top-level `~/.agents/rules/*.md` file and compare that inventory with the rule links below. Numeric prefixes establish the intended order.
3. Read every rule under **Always on** completely. Before acting on the current request, read each task-conditional rule whose section trigger matches the task or environment.
4. Do not preload an **Action-gated** rule merely because the request mentions a later operation. Read it completely immediately before the first matching action, then keep it active for the rest of the current uncompacted context.
5. Re-evaluate task-conditional sections before later requests and action gates before later operations when scope changes.
6. Loading is not applying: honor each loaded rule only according to the applicability declared in the rule file and the section headings below.
7. Read `.agent-memory/index.yaml` to discover available project context. If `.agent-memory/` is absent, proceed without it — don't create it.
8. For memory recall, capture, correction, maintenance or recovery of missing prior context, read [memory procedures](./rules/memory/lifecycle.md). Otherwise load relevant project memory.

---

Headings declare applicability; links must match the top-level rule inventory. They are not automatic `@` imports: `init-rulebook` loads only the selected rules.

## Always on

- [Core principles](./rules/00-core.md)
- [Action vs proposal authorization](./rules/01-authorization.md)
- [Worktree hygiene](./rules/03-worktree-hygiene.md)
- [Skill owners](./rules/12-skill-owners.md)
- [Anti-patterns](./rules/99-anti-patterns.md)

## Action-gated: load immediately before commit-producing, PR/MR title, attribution, or integration work

Action signals: commit/integration workflow; drafting/finalizing commit messages or PR/MR titles; creating a PR/MR or editing its title; commit-producing commands; cherry-picking, reverting, merging, rebasing, or publishing commits; verifying Git author/committer identity or signing. Later plans leave gates closed.

- [Commit attribution](./rules/02-attribution.md)

## Action-gated: load immediately before worktree creation, branch creation, finishing, PR/MR creation or title edits, merge, or cleanup

Action signals: creating a git worktree; creating a branch for isolation; finishing development work; creating a PR/MR or editing its title; merging a pull request; post-merge or stale-branch cleanup; or producing a handoff after branch/PR/merge/cleanup work. Daily checkout safety stays in always-on worktree hygiene.

- [Worktree lifecycle](./rules/07-worktree-lifecycle.md)

## Activate for selections starting from rule 12, overlapping skill choices, named skill requests, or cross-skill references

Use the owner list for discovery; narrow specialists can use their descriptions directly.

- [Skill routing](./rules/11-skill-routing.md)

## Activate for host-authenticated, browser, localhost, or sandbox-sensitive tooling

Trigger signals: GitHub CLI or API work, browser verification, localhost previews, Playwright or browser processes, host authentication, network access, or an unexpected sandbox/permission false-negative.

- [Host tooling](./rules/04-host-tooling.md)

## Activate for code writing, review, execution, debugging, or refactoring

- [Code posture](./rules/20-code-posture.md)

## Activate for package, runtime, dependency, or setup work

- [Environment and package managers](./rules/22-environment.md)

Repository presence alone activates neither section.

## Activate when code, configuration, automation, data transforms, or generated artifacts are changed

- [Verification before completion](./rules/23-verification.md)

## Activate for interface, UX, or visual-artifact work

- [Design posture](./rules/10-design-posture.md)

## Activate for web UI changes, review, verification, or previews

- [Web stack rules](./rules/21-web-stack.md)

## Activate for web UI changes, review, or verification

- [Frontend verification](./rules/24-frontend-verification.md)

## Activate for technical work involving runtime, native, generated, CLI/desktop, binding, or service boundaries

- [Tech stack discovery](./rules/25-tech-stack-discovery.md)

## Activate for Hermes memory, learning or skill maintenance

- [Hermes learning](./rules/06-hermes-learning.md)

## Activate for research or empirical validation projects

- [Research mode](./rules/30-research-mode.md)

## Activate when facts may be current or external

- [Current information](./rules/31-current-info.md)

---

## How to respond (applies globally)

- Lead with the change, not the explanation. Show the code or spec first, then explain only if needed.
- Skip preamble. No "Great question!" or "Sure, happy to help!" — just do the work.
- When flagging a problem, be direct: what's wrong, where, and what the fix is.
- If you're unsure, say so in one line. Don't hedge for three paragraphs.
- **Present findings as structured output, not prose.** Use tables (severity, effort, file:line), bullet lists, or fenced code blocks — not paragraphs. Output should be copy-pasteable as markdown so the user can annotate, comment, and expand directly.
- **Don't pad.** Length is not weight: no restated context, no filler sections, no scope recap to make a short answer feel substantial. A clean result stated in one line is complete — once the probes behind it are actually finished, and it says which ones they were.
