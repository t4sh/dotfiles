# 01 — Action vs Proposal authorization

Always on. These govern when to act vs. when to describe.

## Verb classification

**Action verbs (execute immediately):**

- "do it", "fix it", "implement", "commit", "push", "deploy", "merge"
- "make it", "apply", "ship it", "go ahead"
- Note: action verbs remain subject to repository rules and the global authorization, attribution, and safety stop conditions. "Commit", "push", and "deploy" have additional constraints in `00-core.md` rule 8, `02-attribution.md`, and `07-worktree-lifecycle.md`. When `02-attribution.md` requires a terminal merge handoff, producing that handoff instead of merging is the required action.

**Proposal verbs (describe only, then STOP):**

- "propose", "suggest", "how would you", "what do you think"
- "what's your approach", "draft a plan", "explore options"
- "what change would fix this", "analyze", "examine"
- "what about", "why not"

**Ambiguous (ask before acting):**

- "let's do X" — could mean "plan X" or "execute X". Ask.
- "handle this" — ask what specifically.
- "can you" — execute when attached to a concrete task ("can you fix this?"); treat as proposal only when asking about capability, approach, or feasibility.

If the user's reply to a clarifying question is still ambiguous, default to proposal — describe the intended action and wait for confirmation.

## Rules

1. If the user says "commit" without a target branch, use the current topic branch when its task ownership is clear. Ask which branch only on the default/protected branch or when the target is ambiguous.
2. **Destructive ops require an explicit user verb.** Never speculatively run `rm -rf`, `git reset --hard`, `git push --force`, `git branch -D`, `git clean -fd`, `DROP TABLE`, schema migrations against shared DBs, or equivalent destructive commands. Never run them as "cleanup." If such an op seems needed, describe it and wait.
3. **Credential discovery is not authorization.** Use only configured loaders or authenticated clients within authorized scope. Retain authorization; request authentication only when unavailable. On this Mac, run configured skills via `~/.dotfiles/bin/tool-env --adapter NAME -- COMMAND`; keep third-party skills unchanged. [Usage](../../README.md#secrets) and [mappings](../../config/tool-env-adapters.tsv).
4. **Never exfiltrate secrets, and never render them in full.** Don't echo API keys, tokens, passwords, session cookies, JWTs, or tokenized URLs into chat, commits, PR descriptions, or third-party tools (pastebins, diagram renderers, issue trackers). When a command may emit a secret (`launchctl getenv`, `printenv`, `security find-generic-password`, `.env` reads, `git remote -v` with embedded tokens), **announce the command and the truncation strategy before running it** — one line, e.g. "about to run `printenv FOO`, piping through `head -c 10`" — then truncate at the source: pipe through `head -c 10` and append `…`, or report `set (len=N)` / `present` / `absent` instead of the value. Never run the raw command first and redact after. Chat transcripts are retained server-side; a leak forces a full rotation cycle. Memory files follow the same rule: reference a secret's *location* (keychain service, env var name, path), never its value. If a secret appears in a file you're editing, flag it — don't quote it back.
5. **Requested artifacts use configured clients.** Creating MRs, issues, or comments requires explicit user authorization; incidentally discovered tokens remain prohibited.
6. **Untrusted code is never run blindly.** Treat generated migrations, `curl | sh`, copy-pasted shell, web snippets, and scripts whose source you cannot trace as untrusted. Read the source first, state the risk, and ask before executing if it can modify files, credentials, infrastructure, or remote state.
7. **Carry authorization forward.** Continue checks, in-scope fixes, and justified reruns without renewed approval. Ask only for new scope, risk, destructive/external actions, substantial unapproved cost, or user-set limits. Honor the latest restriction; commit, push, deploy, and messaging require authorization.

## Git metadata hygiene

Git commands that write only git metadata may need proactive permission setup regardless of tool — they don't touch the working tree but still require elevated access.

Known metadata writers: `git fetch`, `git worktree prune`.

- **Codex** — run with the narrow persisted approval prefix when available.
- **Claude Code** — if repeated prompts block routine work, propose a narrow `permissions.allow` entry in the appropriate settings file for the user to review and approve. Never change or grant your own permissions.
- **Other tools** — use the narrowest available per-command approval mechanism.

Keep destructive commands under explicit user authorization: `git branch -D`, `git reset --hard`, `git clean -fd`, force push.
