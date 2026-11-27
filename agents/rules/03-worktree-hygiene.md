# 03 — Worktree hygiene

Always on. Apply these rules whenever the session is inside a git repository or shared local workspace.

- **Check state before edits.** Inspect the branch, upstream, and dirty worktree before changing files when the task involves code, config, commits, or generated artifacts.
- **Validate linked-worktree placement.** For a canonical repository under `~/Projects/`, before edits, locally commit-producing operations, or integration, resolve the current and target-owning worktrees with `git worktree list --porcelain -z`. The canonical checkout and linked worktrees under `<repo-root>/.worktrees/` are compliant. Any linked worktree elsewhere is inspection-only: report its path and hand migration to the user. Do not edit, commit, integrate, move, remove, or recreate it automatically.
- **Commit references include identity and intent.** In every user-facing response, plan, status report, handoff, review, or issue/PR text, render each Git commit as `<short-hash> <subject line>` (for example, `abc12345 fix(web): correct routing`). When listing multiple commits, include this pair for every item; a hash alone is not a complete commit reference.
- **Stop on unexpected repo states.** If the repo is mid-rebase, mid-merge, has unresolved conflicts, is in detached HEAD unexpectedly, or has an in-progress cherry-pick/revert/bisect, pause and report the state before editing. Continue only when the user confirms the intended path or the task explicitly concerns resolving that state.
- **Protect user changes.** Never revert, overwrite, restage, or "clean up" changes you did not make unless the user explicitly asks. If unrelated changes exist, work around them and mention them only when they affect the task.
- **Generated output is still a change.** Treat lockfiles, snapshots, screenshots, build artifacts, and formatter rewrites as intentional only when they are required for the task.
- **No destructive cleanup by reflex.** Do not use `git reset`, `git checkout --`, `git restore`, `git clean`, `rm`, or worktree deletion to get a clean slate unless the user asked for that exact cleanup or approved it after seeing the risk.
- **Keep hygiene in the background.** Apply repository checks silently. Surface branch, status, worktree, or staging details only when they block or materially constrain the requested work, or when the user asks for them.

Worktree creation, branch creation, finishing, merge, cleanup, and post-merge handoff live in `07-worktree-lifecycle.md`. Load that rule immediately before those operations; do not preload it at task start.
