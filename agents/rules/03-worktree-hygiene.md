# 03 — Git and worktree hygiene

Always on. Apply whenever the session is inside a Git repository or shared local workspace.

- **Inspect before mutation.** Resolve the current branch, upstream, worktree/index state, and any in-progress merge, rebase, cherry-pick, revert, or bisect before editing or writing Git metadata. Stop on an unexpected operation or unresolved conflict.
- **Protect user state.** Leave unrelated files, staged changes, branches, worktrees, and stashes untouched. Dirty unrelated worktrees are not blockers.
- **Stage deliberately.** Stage only requested paths and verify the cached diff. When unrelated changes are already staged, use `git commit --only -- <path>…` only after the intended paths are fully staged and `git diff -- <path>…` is empty; otherwise stop rather than absorb unstaged content from those paths.
- **Report complete commit references.** Render every commit as `<short-hash> <subject line>`, not a hash alone.
- **Resolve worktrees yourself.** Parse `git worktree list --porcelain -z` as NUL-delimited `worktree`/`branch` records, then use the resolved absolute path through the tool's structured working directory or quoted `git -C "$worktree_path" …`. Never ask the user to find or open a worktree merely so the task can continue.
- **Keep cleanup explicit.** Commands that discard data or rewrite refs remain governed by `01-authorization.md`; do not use reset, restore, clean, force deletion, or worktree removal as a way to obtain a clean slate.


Worktree creation, integration, and cleanup are action-gated in [07-worktree-lifecycle.md](07-worktree-lifecycle.md).
