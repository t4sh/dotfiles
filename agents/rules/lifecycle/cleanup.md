## Post-merge cleanup

When the user asks for post-merge cleanup, branch/worktree hygiene, stale branch cleanup, or whether anything remains after merge:

- Inspect current status, local branches, remote-tracking branches, worktrees, and stashes before deleting anything. Report the full picture before any deletion.
- Fetch before judging stale state: `git fetch origin --prune` when network/auth is available. If fetch is unavailable, say the cleanup is based on local remote-tracking refs.
- Resolve the integration branch from the repo, don't assume `main` — check `git symbolic-ref refs/remotes/origin/HEAD` or the repo's configured default (`master`, `develop`, etc.). `<default>` below means that resolved local integration branch; `origin/<default>` is its remote-tracking ref.

### Determining session ownership

A branch or worktree "belongs to the current agent session" only if you can attribute it to work done in *this* conversation — e.g. you created it, you committed to it, or it matches a session worktree path/naming convention used here. If you cannot positively attribute it, treat it as **not session-owned** and apply the more conservative rule. When ownership is genuinely ambiguous, list it for follow-up rather than guessing.

### Verifying code is on `<default>`

Confirm reachability with `git`; when integration used a pull or merge request, confirm its state with the repository-selected provider tooling. Do not treat provider metadata field names as git ref paths.

`git branch --merged <default>` only detects fast-forward/merge-commit integration. PR merges are frequently **squash or rebase merges**, where the original branch tips will never show as merged. Before concluding a branch is *not* merged, cross-check with `git cherry -v <default> <branch>` or PR metadata such as `gh pr view <PR> --json state,mergedAt,headRefName` when `gh` is available. For `git cherry -v`: empty output means the branch has no commits not reachable from `<default>`; lines prefixed with `-` mean patch-equivalent commits are already upstream, which is common after squash/rebase merges; lines prefixed with `+` are not upstream. Prefer `git cherry -v` or PR metadata for squash/rebase merges. Treat raw diff checks as supporting evidence only, and state the exact diff form used. State which method confirmed the merge.

### Default-branch realignment after squash PR merge

Provider-created squash merges (including `gh pr merge --auto --squash --delete-branch` on GitHub) land on `origin/<default>` as a new commit. Local `<default>` may still point at the pre-squash tip and appear diverged — that is usually realignment, not a failed merge.

Confirm pull- or merge-request state with the repository-selected provider tooling first, then confirm git refs and local branch state. On GitHub, use `gh`; do not treat provider metadata field names as git ref paths.

Before any destructive ref move, confirm:

- Repository-selected provider tooling confirms integration; on GitHub, `gh pr view <PR> --json state,mergedAt,mergeCommit,headRefName` reports `MERGED`
- `git fetch origin --prune`
- If not on `<default>`, switch only when the worktree is clean; otherwise stop and report
- On `<default>` (re-check after any switch): `git status --short --branch` shows no staged or unstaged tracked changes
- On `<default>`: `git cherry -v origin/<default> <default>` is empty or shows only `-` lines (patch-equivalent commits already upstream)

If all pass: report that the changes are already on `origin/<default>` and **ask before** `git reset --hard origin/<default>`. Do not run it silently — it rewrites the local branch ref and discards uncommitted state.

If any `git cherry -v` line is prefixed with `+`, or the worktree/index is dirty, stop and list the local commits or files that need a human decision.

### Decision matrix

- Session-owned, code is on `<default>`, and repository policy permits cleanup → delete the branch/worktree.
- Repository policy requires retaining the branch or worktree → leave it in place.
- Not session-owned but code is already on `<default>` → delete only when the user explicitly asked for cleanup.
- Not session-owned and code is **not** on `<default>` → leave alone and list for follow-up.
- Local commits, uncommitted files, staged files, conflicts, or stashes found → leave alone and list for follow-up. Do not analyze, drop, restore, or delete them unless asked. Dirty state blocks cleanup only for the branch/worktree that contains it. Stashes are never dropped during cleanup; list them separately. Unrelated stashes or dirty files do not by themselves block deletion of a verified merged clean branch. A session-owned branch with extra unmerged local commits or a dirty worktree is **not** safe to delete — list it instead.

### Safe deletion mechanics

- Prefer safe deletion: use `git branch -d`, not `git branch -D`, unless the user explicitly confirms force deletion. A `-d` failure ("not fully merged") is a signal to stop and re-check the merged state, not to escalate to `-D`.
- You cannot delete the branch that is currently checked out. If cleanup targets the current branch, switch to `<default>` first; if that would disturb uncommitted user work, stop and report instead.
- Remove worktrees before deleting the branch they reference. Use `git worktree remove <path>` (no `--force`) — a removal that fails on a dirty/locked worktree means it has uncommitted state: leave it and list it. Run `git worktree prune` after worktree cleanup.
- Local-only by default. Do not delete remote branches or push deletions (`git push origin --delete`, `git push origin :branch`) unless the user explicitly asks or the repository-selected integration or cleanup contract includes topic-branch deletion. Do not duplicate a deletion already performed by that mechanism.
- After local cleanup, run `git remote prune origin --dry-run` (or `git fetch --prune --dry-run`) to surface remote-tracking refs that are already gone upstream, and list remote branches whose code is on `<default>` but still exist on the remote. Report these as a separate "remote, needs your call" list and ask before acting — never fold remote deletion into the local pass.
