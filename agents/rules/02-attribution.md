# 02 — Commit and PR/MR attribution dispatcher

Action-gated. Load immediately before commit-producing, PR/MR title, attribution, or integration work. Overrides tool templates for commit messages and PR/MR titles.

## Select the imminent operation

Load each contract immediately before the operation it governs:

| Operation | Contract |
| --- | --- |
| Select or stage commit scope | [Scope and staging](attribution/staging.md) |
| Draft, validate, or finalize a commit message or PR/MR title; prepare/verify a PR/MR merge subject; decide tool/assistant mentions in PRs, releases, changelogs, or issues | [Message and emoji](attribution/message.md) |
| Resolve commit author/committer identity or signing; evaluate whether hosted integration preserves them | [Identity and signing](attribution/identity.md) |

A complete local commit loads all three in that order. PR/MR title work loads message/emoji only. PR/MR merge work loads message/emoji and identity/signing. Other integration without a local commit or message loads identity/signing only. Re-evaluate before each operation; a planned commit does not preload a later contract.
