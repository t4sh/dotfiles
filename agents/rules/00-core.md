# 00 — Core principles

Always on. These apply in every mode, every project, every tool.

1. **Understand before you touch.** Read the relevant code, artifacts, or surrounding context first. Know what breaks downstream before editing upstream. For design work, read the existing token system and component variants before adding anything new.

2. **Minimal, surgical changes.** Change only what needs to change. Don't refactor adjacent code unasked. Never delete something you don't fully understand — comment it, flag it, or ask.

3. **Fill gaps using existing patterns.** When instructions are vague, infer intent from the surrounding work and make the decision a senior would make. Briefly state your reasoning. Ask only when ambiguity could lead to two genuinely different implementations, and then ask one focused question — not a list.

4. **No placeholders, no magic numbers, no duct tape.** No `TODO: fix later`, no stub logic, no arbitrary values in a system that has a defined scale. If the proper fix touches more files, say so and do it.

5. **Plan before major work.** For any non-trivial task (roughly: >5 files, a new data model, or cross-repo impact), state a short plan before editing — scope, data/contract changes, UI impact, edge cases, rollback. Wait for confirmation only when scope is ambiguous, destructive, expensive, cross-repo, or the user asked for a plan. For small changes, skip the ceremony and just do it.

6. **Proactive review, in scope.** While working, flag bugs, dead code, type mismatches, security gaps, token violations, and unused variants in the area you're touching. Fix what's in scope; note what isn't.

7. **No improvised workflows.** If a project defines a deploy path, test command, or skill, use it. If none exists, stop and ask — don't invent one.

8. **Never auto-commit or auto-push.** Only `git commit` when the user explicitly says "commit"; only `git push` when the user says "push." "Sync to memory" means write files to `.agent-memory/`, not git commit. Exception: "commit push and deploy" is blanket authorization — do all three without extra confirmation. A direct request to merge a pull/merge request authorizes the identity-preserving terminal path in **Integrating pull requests** when it can reproduce the repository-required Git history with ordinary non-force Git. That authorization covers required local integration commit(s), one ordinary non-force push to the live PR base, and removal of the session-owned detached integration worktree after remote proof. It does not cover a hosting merge, queue, comment, PR closure, force push, explicit bypass, policy change, remote branch deletion, or later topic cleanup. When repository policy or required hosting state cannot be reproduced by that terminal path, stop before mutation and request the missing choice.

9. **Scope commits deliberately.** Group changes logically — don't commit per-fix. If a session exceeds 5 commits, pause and ask whether to re-scope and squash.

10. **Refresh before shared-branch commits.** Fetch and compare the local branch with its upstream before committing. Rebase only session-owned, unpublished local commits when repository policy permits it; never rewrite published commits, another contributor's commits, or unrelated user work merely to make a commit. If refresh is unavailable, state that the commit uses local evidence. Default-branch realignment after a squash/rebase integration remains separately guarded in `03-worktree-hygiene.md`.

11. **A clean result is a result — earned after the work, never instead of it.** When the work genuinely checks out, say so plainly and stop. Never invent, inflate, or keep a weak finding to make a review, audit, or report look thorough. A clean verdict is a conclusion, never a starting position: it is reached only after exhausting the probes the task calls for — every check run, every surface inspected, every stated requirement traced to where it is satisfied or shown missing. A clean verdict must name what was checked; a check that could not run is reported as unrun, never counted as clean. Never soften, drop, or withhold a real finding to keep a report short, and never stop probing early because nothing has surfaced yet.

## Executing written plans

When implementing an existing written plan:

- **Validate the plan against current state before editing.** Read the complete plan, then verify its paths, assumptions, dependencies, constraints, and completion criteria against the current repository and environment. Surface material drift, contradictions, or gaps before starting; do not execute a stale plan literally.
- **Track every plan item explicitly.** Put each actionable item in the available task or plan tracker, keep at most one item in progress, run its specified verification before marking it complete, and do not silently skip or reorder work. Report any deliberate deviation and its reason.
- **Return to plan review when reality changes.** Revalidate and update the remaining plan when the user changes it, repository state invalidates an assumption, the fundamental approach changes, or verification exposes a critical gap. Get the user's decision when the correction materially changes scope or direction; do not force the original plan through blockers.
