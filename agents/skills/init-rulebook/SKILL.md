---
name: init-rulebook
description: "Load the user-level agent rulebook — an `~/.agents/AGENTS.md` index plus every referenced `rules/*.md` — so one consistent, portable baseline applies across any agent app (Claude Code, Codex, Conductor, Copilot, Craft-Agents,Cursor, OpenCode etc.). Re-run after context compaction to rehydrate. Triggers: init rulebook, reload rulebook, load user-level agent rules."
user-invocable: true
alwaysAllow: ["Read", "Glob", "Grep"]
---

# Init user's agent rulebook

Load the **user's agent rulebook** — the global rule set under `~/.agents/` (`AGENTS.md` index plus every rule file it references) — into working context. Run this skill on every invocation; do not assume the rulebook from a prior turn is still present.

## Rehydrate after compaction

Context compaction drops or distills earlier file reads. After compaction (or when rulebook content looks summarized or missing):

1. **Treat prior rulebook knowledge as stale.** Do not rely on remembered rule text from before compaction.
2. **Re-run this skill immediately** — read the index and every referenced rule file again in this turn, before continuing the user's task.
3. **Silent rehydration.** Do not summarize, echo, or confirm the rulebook to the user unless they asked about it.
4. **Then resume work** with the freshly loaded user's agent rulebook applied.

If the user says **rehydrate**, **reload rulebook**, **init rulebook**, **load user's agent rulebook**, or **load user-level agent rules**, execute the steps below even when you believe the rulebook was loaded earlier in the session.

## Steps (every invocation)

1. **Read the index:** `~/.agents/AGENTS.md` (or where it is aliased or symlinked from).
2. **Collect referenced rules:** From the index, every path matching `@./rules/*.md`. That list is the authoritative rulebook — do not substitute glob-only discovery that might miss or add files relative to the index.
3. **Read every referenced file** under `~/.agents/rules/` (resolve `@./rules/foo.md` → `~/.agents/rules/foo.md`). Read in the order they appear in the index (top to bottom).
4. **Absorb silently** — do not summarize, echo, or confirm to the user.
5. **Apply for the remainder of the session** (until the next compaction or explicit re-invocation of this skill).

Optional: if the index and disk disagree (reference missing on disk), skip only that missing file and continue; do not skip files that exist but are unlisted in the index.

## Referenced rules (from index)

> Snapshot of the author's current rulebook, for purpose and reading order. The index (step 2) is authoritative — if your `AGENTS.md` lists different files, follow the index.

| File | Section in index |
|------|------------------|
| `00-core.md` | Always on |
| `01-authorization.md` | Always on |
| `02-attribution.md` | Always on |
| `03-worktree-hygiene.md` | Always on |
| `10-design-posture.md` | Always on |
| `99-anti-patterns.md` | Always on |
| `20-code-posture.md` | Activate when code is involved |
| `22-environment.md` | Activate when code is involved |
| `23-verification.md` | Activate when code is involved |
| `21-web-stack.md` | Activate when browser-rendered UI |
| `24-frontend-verification.md` | Activate when browser-rendered UI |
| `25-tech-stack-discovery.md` | Activate for multi-runtime / native / bindings |
| `30-research-mode.md` | Activate for research validation |
| `31-current-info.md` | Activate when facts may be current or external |

**Read every file the index references, each time this skill runs.** At apply time, honor each rule's activation trigger — but still load the full rulebook into context on every invocation.

## Behavior

- **User's agent rulebook = index + references, every time.** Never skip `AGENTS.md`. Never skip a rule file referenced by the index.
- **No deferral.** Do not load "always on" rules now and promise to load conditional rules later — read the complete referenced set in one pass.
- **Silent operation.** No user-visible output unless explicitly asked about the rulebook.
- **Compaction = reload.** Any turn after compaction should treat loading the user's agent rulebook as required, not optional.
