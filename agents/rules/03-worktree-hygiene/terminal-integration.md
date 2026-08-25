# Terminal integration recipe

Read only after `03-worktree-hygiene.md` selects the identity-preserving terminal path and pins `baseRefOid`, `headRefOid`, `<pr-base>`, `<PR>`, and the repository strategy.

## Workspace

Fast-forward creates no commit and needs no integration worktree. For squash, merge commit, or rebase:

1. Resolve `<repo-root>` from the first NUL-delimited `worktree` record.
2. Require `.worktrees/` to be covered by the Git common directory's `info/exclude`.
3. Create a detached checkout at `<repo-root>/.worktrees/.integration/<PR>` from the pinned object named by the selected recipe.
4. Preserve this worktree on failure when its `HEAD` is the only reference to a unique integration commit. Remove it only after remote proof.

Never detach, switch, clean, or synchronize a user-owned base/topic worktree to construct the result.

## Recipes

Refresh `git var GIT_AUTHOR_IDENT` and `git var GIT_COMMITTER_IDENT` immediately before every commit. Use `-S`/`--gpg-sign` exactly when `02-attribution.md` requires signing.

### Fast-forward

- Require `baseRefOid` to be an ancestor of `headRefOid` and the promoted range to satisfy branch topology/signature policy.
- Set `<integrationOid>` to `headRefOid`; create no commit.

### Squash

- Create the detached integration worktree at `baseRefOid`.
- Run `git merge --squash <headRefOid>` and inspect the staged tree.
- Build a non-interactive message file from the repository's squash title/body convention. Strip attribution trailers forbidden by `02-attribution.md`.
- Run `git commit [-S] -F <message-file>` and set `<integrationOid>` to `HEAD`.
- Require the resulting tree to equal the reviewed topic result relative to the pinned base.

### Merge commit

- Create the detached integration worktree at `baseRefOid`.
- Build a non-interactive message file from the repository's merge title/body convention.
- Run `git merge --no-ff --no-edit [-S] -F <message-file> <headRefOid>` and set `<integrationOid>` to `HEAD`.
- Require parent one to equal `baseRefOid` and parent two to equal `headRefOid`.

### Rebase

- Create the detached integration worktree at `headRefOid`.
- Resolve `<mergeBase>` with `git merge-base <baseRefOid> <headRefOid>`.
- Run `git rebase --force-rebase --onto <baseRefOid> <mergeBase>`, adding `--gpg-sign` when required. Add `--rebase-merges` only when repository policy requires preserving merge topology; apply the repository's empty-commit policy explicitly.
- Set `<integrationOid>` to `HEAD`. Require the old and new commit sequences to be patch-equivalent, every reviewed author to be preserved, every replayed committer to match the effective repository identity, and rewritten OIDs to differ where replay was selected.

## Verification and push

Before pushing:

- Verify `<integrationOid>`'s tree, parents, patch mapping, author/committer metadata, and signatures against the selected recipe.
- Run the repository-required integration gate against `<integrationOid>`.
- Fetch and refresh the pinned PR/base/head, repository strategy, and required gates. Require `origin/<pr-base>` still to equal `baseRefOid`.

Push exactly once without force or upstream mutation:

```
git push origin <integrationOid>:refs/heads/<pr-base>
```

Fetch and require `origin/<pr-base>` to equal `<integrationOid>`. Only then remove the clean task-owned integration worktree. A rejected push, changed pin, failed verification, or failed proof stops the recipe without changing strategy or invoking a hosting fallback.
