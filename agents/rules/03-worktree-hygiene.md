# 03 — Git and worktree hygiene

Always on. Apply whenever the session is inside a Git repository or shared local workspace.

- **Inspect before mutation.** Resolve the current branch, upstream, worktree/index state, and any in-progress merge, rebase, cherry-pick, revert, or bisect before editing or writing Git metadata. Stop on an unexpected operation or unresolved conflict.
- **Protect user state.** Leave unrelated files, staged changes, branches, worktrees, and stashes untouched. Dirty unrelated worktrees are not blockers.
- **Stage deliberately.** Stage only requested paths and verify the cached diff. When unrelated changes are already staged, use `git commit --only -- <path>…` only after the intended paths are fully staged and `git diff -- <path>…` is empty; otherwise stop rather than absorb unstaged content from those paths.
- **Report complete commit references.** Render every commit as `<short-hash> <subject line>`, not a hash alone.
- **Resolve worktrees yourself.** Parse `git worktree list --porcelain -z` as NUL-delimited `worktree`/`branch` records, then use the resolved absolute path through the tool's structured working directory or quoted `git -C "$worktree_path" …`. Never ask the user to find or open a worktree merely so the task can continue.
- **Keep cleanup explicit.** Commands that discard data or rewrite refs remain governed by `01-authorization.md`; do not use reset, restore, clean, force deletion, or worktree removal as a way to obtain a clean slate.

## Worktree creation

A request to create or use a worktree authorizes the isolated checkout; it does not authorize a new branch policy.

- **Reuse existing isolation.** Resolve `--git-dir`, `--git-common-dir`, `--show-superproject-working-tree`, and `--show-toplevel`. Reuse the current linked worktree unless the user asked for another one. Report an unexpected detached HEAD.
- **Resolve `<repo-root>`.** The first `worktree` record from `git worktree list --porcelain -z` is the primary checkout and the sole canonical root. Stop if it is bare, missing, or unusable.
- **Use one parent.** Create every new worktree at `<repo-root>/.worktrees/<full-branch-name>`. A detached PR integration worktree uses `<repo-root>/.worktrees/.integration/<PR>`. Existing legacy worktrees elsewhere may be discovered and used in place but never establish a new parent. Never create `<repo-root>/worktrees/`, a sibling checkout, a repository-parent checkout, a Git-metadata worktree, or a temporary-directory worktree.
- **Ignore locally.** Ensure `.worktrees/` is covered by the Git common directory's `info/exclude`, resolved with `git rev-parse --path-format=absolute --git-path info/exclude`. Do not edit the repository's tracked ignore policy merely to support this personal worktree convention.
- **Follow repository branch policy.** Repository instructions and established branch namespaces are authoritative. When the repository uses git-flow, resolve its configured prefix and base; never initialize git-flow merely because this personal rulebook mentions it. When no policy or established namespace exists, use `feature/<slug>` as the personal default. Agent/operator namespaces such as `codex/*`, `claude/*`, or `<author>/*` are not branch policy.
- **Create atomically.** After proving the branch and path are free, run `git -C "$repo_root" worktree add -b <full-branch-name> <repo-root>/.worktrees/<full-branch-name> <base-ref>`. A host or orchestration tool is acceptable only when it honors the same root, branch, and ownership rules.
- **Prepare the checkout.** Use the repository's environment/setup path and run the narrow clean-baseline check required by `22-environment.md` and `23-verification.md` before implementation.

## Finishing development work

Resolve these terms once:

- `<repo-default>` is the hosting service's configured default branch, cross-checked with `refs/remotes/origin/HEAD` when available.
- `<pr-base>` is the live PR `baseRefName`; it may differ from `<repo-default>`.
- `<PR>` is the live pull/merge request number.

Before integration or cleanup:

- Run the repository's authoritative verification gate. A convenient partial test does not replace a documented gate.
- Preserve the topic branch/worktree for review until integration is proven.
- Treat integration, hosting actions, and cleanup as separate decisions. Implementation completion does not authorize any of them.

## Integrating pull requests

Apply only when the user explicitly asks to merge a pull/merge request.

### Contract

The repository owns the history shape; `02-attribution.md` owns the identity used for commits the agent creates or replays. The default terminal path is available only when ordinary non-force Git can produce the repository-required result and land it on `<pr-base>` without pretending to reproduce hosting-only semantics.

Use this decision boundary:

1. **Pin live state.** Fetch current refs, resolve the open non-draft PR, fetch its exact head ref, and pin `baseRefOid`, `headRefOid`, `<pr-base>`, reviews, checks, and required deployment/policy evidence. Require `origin/<pr-base>` to equal `baseRefOid`.
2. **Select the repository strategy.** Read project instructions first, then branch constraints and hosting-enabled methods. Constraints narrow the permitted set. If policy still leaves materially different history shapes, ask one focused question before mutation.
3. **Fail cheap on topology.** For fast-forward, require `baseRefOid` to be an ancestor of `headRefOid`; honor linear-history and signature requirements before deeper probes.
4. **Find the hosting boundary.** A required queue, mandatory hosting command, or repository workflow that depends on a hosting `MERGED` event the terminal result cannot produce makes the terminal path unavailable. Report the identity/policy conflict and request the user's choice. Otherwise use only the ordinary push in step 7 and let the server accept or reject it; existing server-side permission is not an explicit bypass. Do not simulate missing hosting state with a comment or manual PR closure.
5. **Resolve identity and signing.** Apply `02-attribution.md` in the integration worktree. Existing commits retain their objective metadata; locally created squash/merge commits use the effective repository identity; a local rebase preserves reviewed authors and uses the effective committer.
6. **Construct and verify locally.** Read `rules/03-worktree-hygiene/terminal-integration.md` and follow only the selected strategy. Use a session-owned detached worktree under `<repo-root>/.worktrees/.integration/<PR>` for every commit-producing strategy. Verify the resulting tree, parents, patch equivalence, authors, committers, signatures, and repository gate before push.
7. **Refresh, then push once.** Fetch and re-read the pinned PR, base, head, strategy, and gates immediately before mutation. Any change is a stop-and-refresh condition. Push only the verified OID with `git push origin <integrationOid>:refs/heads/<pr-base>`. A rejection stops the procedure; never retry with force, admin/bypass flags, a different identity, or changed protection.
8. **Prove Git integration.** Fetch and require `origin/<pr-base>` to equal `<integrationOid>`. This Git proof is the completion criterion for the terminal path. Report the hosting PR state separately; it may remain `OPEN` for locally reconstructed squash/rebase or for a non-default base. Do not comment on or close the PR without separate authorization.
9. **Dispose only task-owned scaffolding.** After remote proof, remove the clean detached integration worktree created by this procedure. Preserve and report it when verification or push fails and it contains the only reference to a unique integration commit. Topic branch/worktree cleanup remains separate.

GitHub's non-interactive evidence and explicitly authorized `gh pr merge` commands live in `rules/03-worktree-hygiene/github-preflight.md`. That reference supplies commands, not policy.

### Hosting integration

A queue, web merge, `gh pr merge`, explicit bypass, protection change, or strategy different from the repository-selected terminal result requires explicit user authorization. When authorized, pin the current head OID, use the requested method, monitor with a bounded deadline, prove the final hosting state, and leave branch deletion to post-merge cleanup. Do not pass `--delete-branch` as part of merge.

## Post-merge cleanup

Cleanup is local-only unless the user explicitly requests remote deletion.

1. Fetch/prune when available and resolve the integration tip: the PR's `<pr-base>` when a PR is known, otherwise the repository's configured integration/default branch.
2. Inventory branches, worktrees, dirty state, and stashes. A target is session-owned only when this conversation created or modified it; ambiguity means leave it.
3. Prove integration. Reachability proves fast-forward/merge-commit integration. For squash/rebase, require patch equivalence with `git cherry -v <integration-tip> <branch>` or authoritative PR metadata; raw diff equality is supporting evidence only.
4. Remove a clean linked worktree from a separate resolved control worktree, then delete its branch. Use `git branch -d` for reachable history. A squash/rebase branch that is only patch-equivalent requires an explicit `git branch -D` authorization after the evidence is shown; do not claim cleanup complete when safe deletion refuses it.
5. Never delete `<repo-default>`. Leave dirty, locked, unmerged, ambiguous, or non-session-owned targets and all stashes for follow-up.
6. List surviving remote topic branches under `remote, needs your call`; never fold remote deletion into local cleanup.

## Default/base realignment after squash or rebase

After a squash/rebase integration, a local `<pr-base>` may diverge from `origin/<pr-base>` because the remote contains replacement commits.

- Prove remote integration and patch equivalence first.
- Require the local base worktree to be clean and contain no `git cherry` `+` commits.
- Explain the ref move and ask before `git reset --hard origin/<pr-base>`; never rebase the stale local base to disguise realignment.

## Handoff

After code, commit, branch, PR, integration, or cleanup work, report the current branch/upstream, worktree/index state, ahead/behind/diverged state, verification performed, and any surviving stashes, worktrees, topic branches, hosting-state gap, or remote cleanup decision.
