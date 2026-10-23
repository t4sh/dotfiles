# 07 — Worktree lifecycle dispatcher

Action-gated. Load immediately before creating a git worktree, creating a branch for isolation, finishing development work, creating a PR/MR or editing its title, merging a pull request, cleaning up branches/worktrees, or producing a handoff after that work.

## Select the imminent operation

Load only the matching contract immediately before its operation:

| Operation | Contract |
| --- | --- |
| Create a worktree or branch | [Creation and placement](lifecycle/creation.md) |
| Create a PR/MR or edit its title | [PR/MR title](lifecycle/pr-title.md) |
| Finish work, prepare integration, merge, or verify merge checks/results | [Integration and verification](lifecycle/integration.md) |
| Inspect cleanup, remove branches/worktrees, or realign after squash merge | [Cleanup](lifecycle/cleanup.md) |
| Hand work back after lifecycle operations | [Handoff state](lifecycle/handoff.md) |

A title-only edit loads PR/MR title and the message contract in `02-attribution.md`; it leaves integration checks and cleanup deferred. Integration loads cleanup only when realignment, retention, or deletion is imminent. A later planned operation does not open its gate.
