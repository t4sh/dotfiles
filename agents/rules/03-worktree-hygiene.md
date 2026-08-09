# 03 — Worktree hygiene

Always on. Apply these rules whenever the session is inside a git repository or shared local workspace.

- **Check state before edits.** Inspect the branch, upstream, and dirty worktree before changing files when the task involves code, config, commits, or generated artifacts.
- **Stop on unexpected repo states.** If the repo is mid-rebase, mid-merge, has unresolved conflicts, is in detached HEAD unexpectedly, or has an in-progress cherry-pick/revert/bisect, pause and report the state before editing. Continue only when the user confirms the intended path or the task explicitly concerns resolving that state.
- **Protect user changes.** Never revert, overwrite, restage, or "clean up" changes you did not make unless the user explicitly asks. If unrelated changes exist, work around them and mention them only when they affect the task.
- **Stage deliberately.** Stage only files that belong to the requested change. If other staged files are present, leave them staged and report that they were pre-existing.
- **Pre-staged index ⇒ commit with an explicit pathspec.** A bare `git commit` (and `git commit -m`) commits the *entire* index, not just files you just `git add`-ed. Whenever the index may already contain unrelated changes — pre-existing staged files, a prior turn's staging, anything you did not stage this step — scope the commit explicitly: `git commit -m "…" -- <path> [<path>…]` (or `git commit --only <path>`). Never rely on a bare commit to "just commit what I added"; it will sweep pre-staged files into the wrong commit and mis-scope history. Also note `git add a b c` aborts and stages nothing if any pathspec matches no file (e.g. an already-deleted path) — stage deletions with `git add -A -- <path>` / `git rm`, and verify `git diff --cached --stat` before committing.
- **Generated output is still a change.** Treat lockfiles, snapshots, screenshots, build artifacts, and formatter rewrites as intentional only when they are required for the task.
- **No destructive cleanup by reflex.** Do not use `git reset`, `git checkout --`, `git restore`, `git clean`, `rm`, or worktree deletion to get a clean slate unless the user asked for that exact cleanup or approved it after seeing the risk.

## Worktree creation

Apply this section whenever the user explicitly asks to use or create a git worktree. A worktree request is authorization to create the isolated checkout; do not ask for a second confirmation.

- **Reuse existing isolation.** Resolve `git rev-parse --git-dir`, `git rev-parse --git-common-dir`, `git rev-parse --show-superproject-working-tree`, and `git rev-parse --show-toplevel` first. If `GIT_DIR != GIT_COMMON` and the checkout is not a submodule, reuse the current linked worktree instead of nesting another one. Report an unexpected detached HEAD before editing.
- **Always use a project-local parent.** Create manual worktrees inside the same repository/project directory under `<repo-root>/.worktrees/` or `<repo-root>/worktrees/`. Selection order is: an explicit user or project convention, then an existing allowed directory, then the `.worktrees/` default. If both allowed directories already exist and no convention selects one, prefer `.worktrees/`. Never choose an adjacent sibling checkout, a global worktree directory, `.worktree/`, `.context/`, or a temporary directory. A host-native worktree tool is acceptable only when it can honor the selected project-local path and branch policy; otherwise use `git worktree` directly. Paseo-managed worktrees also remain subject to the additional lifecycle rules in `05-paseo-orchestration.md`.
- **Require ignore coverage.** Before creation, verify the selected parent with `git check-ignore -q <worktree-parent>/` (or a representative child path). If it is not ignored, add the selected parent (`.worktrees/` or `worktrees/`) to the repo's appropriate ignore file before creating the worktree; do not commit that change unless the user separately authorized a commit.
- **Make the path mirror the full Git Flow branch name.** Classify and name the branch under the Branch creation rules below, then use `<repo-root>/<worktree-parent>/<full-branch-name>` as the worktree path—for example, branch `feature/catalog-search` under `.worktrees/` maps to `.worktrees/feature/catalog-search`. Create any required directory inside the selected parent; do not flatten `/` to `-` or invent an agent/operator prefix.
- **Create branch and worktree atomically.** After resolving the correct base ref and confirming that neither the branch nor path conflicts, use `git worktree add -b <full-branch-name> <repo-root>/<worktree-parent>/<full-branch-name> <base-ref>`. This is the sole exception to the `git-flow-next` branch-creation command below: it preserves the current checkout while applying the repository's Git Flow type, prefix, and base. It does not permit `git checkout -b` or ad-hoc branch names.
- **Do not silently abandon isolation.** If creation is blocked by permissions, sandbox policy, branch ownership, a dirty/conflicted target, or an unsupported host tool, report the exact blocker. Do not continue in the current checkout when the user asked for a worktree.
- **Prepare and verify before implementation.** In the new checkout, follow `22-environment.md` for project-aware dependency/setup commands and `23-verification.md` for the narrowest meaningful clean-baseline check. If the baseline fails, distinguish a pre-existing failure from setup trouble and ask before implementing on a known-bad baseline.

## Branch creation

Mandatory. This overrides any built-in tool default that names branches after the agent or operator.

- **Create branches with `git-flow-next`, never ad-hoc.** Use `git flow feature start <name>` for features, `git flow bugfix start <name>` for fixes, `git flow hotfix start <name>` / `git flow release start <ver>` as appropriate (the binary is `git-flow`, invoked as `git flow …`; declared in the Brewfile as `git-flow-next`). The type prefix (`feature/`, `bugfix/`, `hotfix/`, `release/`) and base are owned by git-flow config — never hand-craft them. The only creation exception is the atomic `git worktree add -b` flow above after resolving that same Git Flow prefix and base.
- **Forbidden branch names:** agent-identity or operator-identity namespaces — `claude/*`, `cursor/*`, `codex/*`, `gemini/*`, `tash/*`, `ash/*`, `<author>/*` — and bare `git checkout -b <adhoc>`. The branch namespace belongs to the project's workflow, not to the tool or the author. An agent must not fall back to its own naming convention.
- **Respect the repo's real base branch.** git-flow defaults a feature's base to `develop`; many repos are trunk-based with only `main`/`master`. Do **not** create a `develop` branch to satisfy the tool. If the repo has no git-flow config, run `git flow init` selecting the existing integration branch as the base (or `git flow config` to point the base at it) and say so; if the correct base is ambiguous, ask before initializing.
- **`git-flow-next` governs branch *creation*; it does NOT relax the finishing rules.** `git flow … finish` by default creates a merge commit, creates a tag, and deletes the local *and remote* branch — that is auto-commit + auto-push + remote deletion in one command. It is therefore gated exactly like `commit`/`push`: never run `git flow finish` (or `git flow delete`) unprompted. Run it only when the user explicitly asks to finish/merge/delete the branch.
- **Do not `git flow finish` when the project integrates via pull/merge requests.** It merges locally and bypasses review/CI, and double-integrates against a later squash/rebase PR merge. There, "finishing" means push the branch and open/merge the PR. Use `git flow finish`'s local merge only when the project's real model is local git-flow merges.
- **When explicitly asked to finish, use the non-destructive posture:** keep the remote branch unless the user asked to delete it (`--keepremote`), never `-D`/`--force-delete` (a normal delete failure is a stop-and-recheck signal, per Post-merge cleanup), never `--no-verify` unless the user explicitly asks, and the merge/tag message carries no attribution trailers (`02-attribution`). `git flow delete` must run with `--no-force` and `--no-remote` unless the user explicitly authorized force/remote deletion. The Post-merge cleanup section below still fully governs.
- **If `git-flow-next` is absent from the environment, stop and say so** (it's Brewfile-declared) — do not silently substitute `git checkout -b` with an improvised name.

## Finishing development work

Apply this section when implementation is complete and integration, publication, or cleanup is being considered.

- **Gate integration with the project's authoritative check.** Before integrating, run the repository-defined integration or CI-equivalent gate from its documented workflow, scripts, or CI configuration. Do not substitute a convenient partial test when the project defines a broader gate. If no authoritative gate exists, run the most complete project-appropriate verification available and state what was used. Stop and report failures before integration.
- **Re-verify local merges before cleanup.** After any local merge, rerun the same integration/CI-equivalent gate against the merged result. If it fails, preserve the branch and worktree and stop; do not delete or clean up evidence needed to investigate the merged state.
- **Integration remains the user's decision.** If the user has not explicitly authorized merge, push/PR creation, or another integration path, preserve the branch and worktree and ask one focused question about how they want the completed work integrated. Do not infer integration authorization from implementation completion.
- **Keep PR worktrees available for review.** After pushing and opening a pull/merge request, preserve its branch and worktree so review feedback can be applied there. Clean them up only after integration is proven and the cleanup rules below authorize removal.
- **Require explicit confirmation before discarding unfinished work.** Before destructive discard, show the exact branch, its commits that would be lost, and the worktree path, then ask for explicit confirmation. Do not treat vague cleanup language as authorization to force-delete commits or a worktree.
- **Prove both integration and ownership before normal cleanup.** Do not remove a branch or worktree until the work is proven integrated and the branch/worktree is proven session-owned under the rules below. Explicitly confirmed discard is the only exception to the integration requirement; ownership and destructive-action authorization still must be proven.

## Merging pull requests (`gh`)

When the user explicitly asks to merge a PR (see `01-authorization` — **merge** is an action verb):

- **Always use `gh pr merge`**, not the GitHub web UI, unless the user asks for UI or the repo requires merge queue/admin flows you cannot satisfy from CLI.
- **Always pass `--delete-branch`** so the PR head branch is removed on GitHub (and locally when applicable). This applies regardless of merge strategy.
- **Pick the strategy explicitly** — repo default or user preference. Always pass `--auto` so GitHub merges when required checks pass (or immediately when they already do). Run the same command **without** `--auto` only when the user explicitly approves manual merge fallback.
  - merge commit: `gh pr merge <PR> --auto --merge --delete-branch`
  - squash: `gh pr merge <PR> --auto --squash --delete-branch`
  - rebase: `gh pr merge <PR> --auto --rebase --delete-branch`
- When `--auto` completes asynchronously (CLI returns before merge), poll `gh pr view` for `MERGED` rather than inferring success from the immediate return. Do not poll until green and then run a second manual merge unless the user explicitly asked to watch first.
- `<PR>` is the PR number, URL, or branch name. Omit it when checked out on the PR head branch (then `gh pr merge …` resolves the PR from context).
- If `--auto` fails for any reason, report the error and stop. Do not rerun without `--auto` in the same turn unless the user explicitly approves manual merge fallback — even when required checks are already green. Do not bypass with `--admin` unless the user explicitly asks.
- After merge, confirm GitHub PR state via `gh pr view <PR> --json state,mergedAt,mergeCommit,headRefName` when helpful (`MERGED` is a GitHub PR state, not a git merge result). If local `<default>` looks diverged after a squash merge, follow **Default-branch realignment after squash PR merge** below before treating it as a failed merge. Other local post-merge cleanup still follows **Post-merge cleanup** below (`git branch -d`, worktree removal, etc.).
- **Manual local squash + signed push is an explicit exception to `gh pr merge`.** When the user specifically asks for a manual local squash, manual local squash + signed push, or equivalent wording, do **not** use `gh pr merge --squash`: GitHub controls that squash commit's identity and branch cleanup. Treat the request as authorization to perform the local squash, push `<default>`, and clean up the session-owned PR/topic branch after integration is verified. Otherwise, the normal `gh pr merge --auto --delete-branch` rules above apply.
- **Manual local squash uses the repo's effective Git identity.** Before creating or amending the signed squash commit, resolve the active repo identity from Git config: `git config --show-origin --get user.name`, `git config --show-origin --get user.email`, `git var GIT_AUTHOR_IDENT`, and `git var GIT_COMMITTER_IDENT`. Use that configured name and email for author and committer. Do not replace the configured email with a display name, org label, or remembered shorthand; `includeIf` configs may intentionally pair a visible name such as `work-profile` with a GitHub-verified noreply email.
- **Manual local squash implies scripted cleanup.** For this preferred flow, after the PR branch is pushed and CI is green, automate as much as possible while keeping the squash commit local and signed: fetch/prune; resolve `<default>`; require a clean worktree/index; fast-forward local `<default>` to `origin/<default>` only when safe (do not `reset --hard` without separate explicit approval); `git merge --squash origin/<head>`; review the staged diff; create one `git commit -S` with the repo's effective author/committer identity and no attribution trailers; push `<default>`; verify the commit signature on GitHub when possible; verify the PR is closed/integrated (a direct push with a closing keyword may be `CLOSED` with `mergedAt=null`, not GitHub `MERGED`); then explicitly delete the session-owned topic branch both locally and remotely and fetch/prune again. GitHub `--auto`/`--delete-branch` only applies to `gh pr merge`; it does **not** clean up branches for a direct manual squash push, so cleanup must be an explicit final step. If `git push --signed` is unsupported by the remote, report that and proceed with a normal push of the signed commit.

`--delete-branch` removes the **topic branch only**, never the base branch (`main`/`develop`).

## Post-merge cleanup

When the user asks for post-merge cleanup, branch/worktree hygiene, stale branch cleanup, or whether anything remains after merge:

- Inspect current status, local branches, remote-tracking branches, worktrees, and stashes before deleting anything. Report the full picture before any deletion.
- Fetch before judging stale state: `git fetch origin --prune` when network/auth is available. If fetch is unavailable, say the cleanup is based on local remote-tracking refs.
- Resolve the integration branch from the repo, don't assume `main` — check `git symbolic-ref refs/remotes/origin/HEAD` or the repo's configured default (`master`, `develop`, etc.). `<default>` below means that resolved local integration branch; `origin/<default>` is its remote-tracking ref.

### Determining session ownership

A branch or worktree "belongs to the current agent session" only if you can attribute it to work done in *this* conversation — e.g. you created it, you committed to it, or it matches a session worktree path/naming convention used here. If you cannot positively attribute it, treat it as **not session-owned** and apply the more conservative rule. When ownership is genuinely ambiguous, list it for follow-up rather than guessing.

### Verifying code is on `<default>`

Confirm reachability with `git`; confirm PR integration with `gh` — do not treat GitHub JSON field names as git ref paths.

`git branch --merged <default>` only detects fast-forward/merge-commit integration. PR merges are frequently **squash or rebase merges**, where the original branch tips will never show as merged. Before concluding a branch is *not* merged, cross-check with `git cherry -v <default> <branch>` or PR metadata such as `gh pr view <PR> --json state,mergedAt,headRefName` when `gh` is available. For `git cherry -v`: empty output means the branch has no commits not reachable from `<default>`; lines prefixed with `-` mean patch-equivalent commits are already upstream, which is common after squash/rebase merges; lines prefixed with `+` are not upstream. Prefer `git cherry -v` or PR metadata for squash/rebase merges. Treat raw diff checks as supporting evidence only, and state the exact diff form used. State which method confirmed the merge.

### Default-branch realignment after squash PR merge

Squash merges (including `gh pr merge --auto --squash --delete-branch`) land on `origin/<default>` as a new commit. Local `<default>` may still point at the pre-squash tip and appear diverged — that is usually realignment, not a failed merge.

Confirm GitHub PR state with `gh` first, then confirm git refs and local branch state — do not treat GitHub JSON field names as git ref paths.

Before any destructive ref move, confirm:

- `gh pr view <PR> --json state,mergedAt,mergeCommit,headRefName` reports `MERGED`
- `git fetch origin --prune`
- Remote-tracking topic branch is gone: resolve `<head>` from `headRefName`, then confirm `git branch -r --list origin/<head>` is empty
- If not on `<default>`, switch only when the worktree is clean; otherwise stop and report
- On `<default>` (re-check after any switch): `git status --short --branch` shows no staged or unstaged tracked changes
- On `<default>`: `git cherry -v origin/<default> <default>` is empty or shows only `-` lines (patch-equivalent commits already upstream)

If all pass: report that the changes are already on `origin/<default>` and **ask before** `git reset --hard origin/<default>`. Do not run it silently — it rewrites the local branch ref and discards uncommitted state.

If any `git cherry -v` line is prefixed with `+`, or the worktree/index is dirty, stop and list the local commits or files that need a human decision.

### Decision matrix

- Session-owned **and** code is on `<default>` → delete the branch/worktree.
- Not session-owned but code is already on `<default>` → delete only when the user explicitly asked for cleanup.
- Not session-owned and code is **not** on `<default>` → leave alone and list for follow-up.
- Local commits, uncommitted files, staged files, conflicts, or stashes found → leave alone and list for follow-up. Do not analyze, drop, restore, or delete them unless asked. Dirty state blocks cleanup only for the branch/worktree that contains it. Stashes are never dropped during cleanup; list them separately. Unrelated stashes or dirty files do not by themselves block deletion of a verified merged clean branch. A session-owned branch with extra unmerged local commits or a dirty worktree is **not** safe to delete — list it instead.

### Safe deletion mechanics

- Prefer safe deletion: use `git branch -d`, not `git branch -D`, unless the user explicitly confirms force deletion. A `-d` failure ("not fully merged") is a signal to stop and re-check the merged state, not to escalate to `-D`.
- You cannot delete the branch that is currently checked out. If cleanup targets the current branch, switch to `<default>` first; if that would disturb uncommitted user work, stop and report instead.
- Remove worktrees before deleting the branch they reference. Use `git worktree remove <path>` (no `--force`) — a removal that fails on a dirty/locked worktree means it has uncommitted state: leave it and list it. Run `git worktree prune` after worktree cleanup.
- Local-only by default. Do not delete remote branches or push deletions (`git push origin --delete`, `git push origin :branch`) unless the user explicitly asks; deleting a remote branch can break others' tracking and open PRs. **Exception:** when the user asked to merge a PR, remote topic-branch deletion is handled by `gh pr merge --delete-branch` (see **Merging pull requests** above) — do not also run a separate `git push origin --delete` for the same branch.
- After local cleanup, run `git remote prune origin --dry-run` (or `git fetch --prune --dry-run`) to surface remote-tracking refs that are already gone upstream, and list remote branches whose code is on `<default>` but still exist on the remote. Report these as a separate "remote, needs your call" list and ask before acting — never fold remote deletion into the local pass.

## Handoff state

Before handing work back after code, config, commit, branch, PR, merge, or cleanup work:

- Confirm the current branch and upstream.
- Confirm whether the worktree is clean or list remaining uncommitted/staged files.
- Confirm whether the branch is aligned with upstream, ahead, behind, or diverged. If local `<default>` diverged after a squash PR merge, follow **Default-branch realignment after squash PR merge** before treating divergence as unresolved work.
- Mention remaining stashes, stale branches, or worktrees without deleting them unless the cleanup rules above apply.
