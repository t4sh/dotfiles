# Commit scope and staging contract

- **Stage deliberately.** Stage only requested-change files. Leave unrelated pre-staged files staged and report them.
- **A pre-staged index requires an explicit commit pathspec.** Bare `git commit` includes the entire index. When unrelated changes may already be staged, use `git commit -m "…" -- <path>…` or `git commit --only <path>`. Never assume it commits only your latest `git add`.
- `git add a b c` stages nothing if any pathspec is missing. Stage deletions with `git add -A -- <path>` or `git rm`, then verify `git diff --cached --stat` before committing.
- **Scope commits deliberately.** Group changes logically rather than per fix. Beyond five session commits, pause and ask whether to re-scope and squash.
