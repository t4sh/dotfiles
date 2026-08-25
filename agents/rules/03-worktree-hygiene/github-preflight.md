# GitHub integration preflight

Reference only. Read when `03-worktree-hygiene.md` is integrating a GitHub pull request. The rule owns decisions; this file supplies non-interactive evidence commands.

## Pin the request

Use `gh pr view <PR> --json state,isDraft,baseRefName,baseRefOid,headRefName,headRefOid,headRepository,isCrossRepository,reviewDecision,mergeStateStatus,statusCheckRollup`. Fetch `refs/pull/<PR>/head` from the canonical origin and require `FETCH_HEAD` to equal `headRefOid`.

## Resolve repository strategy

Read repository settings without a selector:

```
gh api repos/{owner}/{repo} --jq '{allow_merge_commit,allow_squash_merge,allow_rebase_merge,squash_merge_commit_title,squash_merge_commit_message,merge_commit_title,merge_commit_message}'
```

Read rules applicable to the exact URL-encoded base branch:

```
gh api --paginate "repos/{owner}/{repo}/rules/branches/<url-encoded-pr-base>"
```

Inspect `type` and `parameters`. A `pull_request` rule's `parameters.allowed_merge_methods` narrows the repository-wide methods. `required_linear_history`, `required_signatures`, `merge_queue`, `lock_branch`, and required deployment/check rules constrain or exclude terminal strategies as stated in the controlling rule.

## Protection and gates

- Query `repos/{owner}/{repo}/branches/<url-encoded-pr-base>` for the readable `protected` signal.
- Query classic details non-interactively through GraphQL only when needed. A null or unreadable classic detail is an audit limitation when the branch signal and applicable-rules endpoint are both readable; it is not proof that no protection exists. Let the ordinary push accept or reject server-side. Authentication failure or inability to read applicable rules is unavailable policy evidence.
- Use `gh pr checks <PR> --required` for required checks and the pinned PR metadata for review state.
- Query review threads through paginated GraphQL and require every returned `isResolved` value to be true when conversation resolution is required.
- Treat a repository workflow or documented contract that requires `pull_request.closed` with `merged == true` as hosting-only for a terminal result GitHub will not record as merged.

Never use an interactive `gh ruleset view` picker. Ruleset-detail lookup is optional audit evidence; the applicable-rules response is the strategy/gate input. Existing server-side permission is not an instruction to invoke bypass: attempt only the ordinary non-force push from the controlling rule and accept the server's decision. Never use bypass actors, admin flags, or protection changes to make it succeed.

## Explicitly authorized hosting merge

Use only when the user selects GitHub integration after the terminal/hosting boundary is reported. Refresh `headRefOid` immediately before arming it:

- merge commit: `gh pr merge <PR> --auto --merge --match-head-commit <headRefOid>`
- squash: `gh pr merge <PR> --auto --squash --match-head-commit <headRefOid>`
- rebase: `gh pr merge <PR> --auto --rebase --match-head-commit <headRefOid>`
- required queue: `gh pr merge <PR> --auto --match-head-commit <headRefOid>`

Do not pass `--delete-branch`. Monitor with a stated deadline—thirty minutes when the user supplied none. On error or timeout, refresh PR state and report it; a retry with another strategy, `--admin`, or no `--auto` needs new authorization.
