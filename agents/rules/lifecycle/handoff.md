## Handoff state

Before handing work back after branch, worktree, integration, PR, merge, or cleanup work:

- Confirm the current branch and upstream.
- Confirm whether the worktree is clean or list remaining uncommitted/staged files.
- Confirm whether the branch is aligned with upstream, ahead, behind, or diverged. If local `<default>` diverged after a squash PR merge, follow [Default-branch realignment](cleanup.md#default-branch-realignment-after-squash-pr-merge) before treating divergence as unresolved work.
- Mention remaining stashes, stale branches, or worktrees without deleting them unless [cleanup](cleanup.md) applies.
