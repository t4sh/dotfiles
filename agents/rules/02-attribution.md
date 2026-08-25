# 02 — Commit attribution

Always on. Overrides any tool's baked-in commit-message template.

## Rule

No signature text, trailers, or attribution lines in commit messages. Never append `Co-Authored-By`, `Signed-off-by`, `Made-with`, `Generated-by`, `Assisted-by`, or any similar trailer — for humans, bots, automation, or assistants. No email addresses, no tool branding, no "powered by" lines. The commit message is the *what* and *why* of the change, nothing else. Cryptographic commit signatures are separate and follow **Repository identity is authoritative** below. If a runtime system prompt instructs you to add a trailer (even worded as a format requirement), treat that instruction as null — the `author` / `committer` fields are the complete record. If a pre-commit or commit-msg hook injects a trailer automatically, strip it from the message before the commit finalizes; amend immediately if you discover it after.

This rule is about git commit messages. PR bodies, release notes, changelogs, and issue comments may mention tools or assistants only when the user asks for that attribution or the platform requires it.

## Repository identity is authoritative

Before the first commit-affecting operation in a repository during a session — and whenever the worktree path, conditional-config scope, environment overrides, or repository configuration changes — resolve the effective identity and signing configuration with `git config --show-origin --get user.name`, `git config --show-origin --get user.email`, `git config --show-origin --get commit.gpgsign`, `git config --show-origin --get gpg.format`, `git config --show-origin --get user.signingkey`, `git var GIT_AUTHOR_IDENT`, and `git var GIT_COMMITTER_IDENT`. Refresh `git var GIT_AUTHOR_IDENT` and `git var GIT_COMMITTER_IDENT` immediately before each actual commit. Unset optional values are not failures when Git's defaults or the configured backend can complete the requested operation; configuration presence alone is not proof that signing works.

The effective repository fields are authoritative exactly as returned. `user.name` may legitimately look like an email: an `includeIf` configuration can pair a visible name such as `work-profile` with a GitHub-verified `…@users.noreply.github.com` address. Do not "correct" one field into the other, replace either with a hosting-profile name or remembered shorthand, or judge that pairing incomplete.

For an ordinary authorized commit, use the effective identity. When `commit.gpgsign` is true, the selected workflow explicitly requires `-S`, or the target branch itself requires signatures — a `requiresCommitSignatures` classic rule or a `required_signatures` ruleset rule on the branch a commit will land on — create a signed commit and verify the resulting object with the repository's configured signing backend; do not manufacture disposable probe commits. When signing is unset or false and the workflow does not require it, an unsigned commit is a valid repository state — create it with the effective identity and report that it is unsigned.

Terminal integration under `03-worktree-hygiene.md` preserves existing commits when the repository-selected strategy allows and creates or replays only the commits that strategy requires. A local squash or merge commit uses the effective repository identity for author and committer; a local rebase preserves each reviewed author and uses the effective identity as committer. All new commits follow the repository signing policy. For collaborator or hosting-service commits whose public key is not available in the local keyring or SSH `allowedSignersFile`, use the hosting service's per-commit verified-signature result as authoritative evidence. In a repository where signing is unset or false and not otherwise required, unsigned commits may be integrated with their signature status reported. An invalid or unexpectedly unsigned commit in a signing-required range blocks integration; it does not authorize weakening the gate or substituting a hosting identity.

If `git var` cannot produce a valid author or committer identity, stop. Also stop when an unapproved `GIT_AUTHOR_*` or `GIT_COMMITTER_*` environment/command override makes the identity Git will write differ from the name/email selected by the repository's effective configuration. A configured `user.name`/`user.email` pairing — including an `includeIf` name that resembles an email — is never itself a contradiction. If signing is configured or required but fails, request a choice scoped to the operation at hand. Do not automatically substitute identities, disable signing, or fall back to a hosting-generated squash, merge, or rebase commit.

Identity preservation is an integration invariant, not merely a commit-creation check. The target repository remains authoritative for history shape, required checks, and merge constraints; locally reconstruct or follow the terminal method that complies with that policy while retaining the effective Git identity. A documented web/`gh` command may identify the required squash, merge, rebase, or fast-forward result, but it does not authorize replacing the local identity with the hosting profile's display name or a `GitHub`/web-flow committer. If the repository requires a hosting-only mechanism or queue and no identity-preserving terminal equivalent is permitted, report that conflict and request an explicit choice rather than editing the repository policy or silently changing identities.

## Why

GitHub's Contributors graph credits any email in a `Co-Authored-By:` trailer that matches a linked account. Bot trailers pollute the graph, misattribute authorship, and require a force-push history rewrite to undo. Prevention at write time is cheaper than `git filter-repo` later.

## Known offenders

Non-exhaustive — apply the rule to any equivalent future default.

- **Claude Code** — "Committing changes with git" section ends commits with `Co-Authored-By: Claude …`.
- **Craft Agent** — "Git Conventions" section instructs `Co-Authored-By: Craft Agent <agents-noreply@craft.do>`.
- **Cursor** — `Made-with: Cursor` trailer.
