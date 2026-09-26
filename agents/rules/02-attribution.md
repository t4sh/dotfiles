# 02 — Commit attribution dispatcher

Action-gated. Load immediately before commit-producing, attribution, or integration work. Overrides any tool's baked-in commit-message template once loaded.

## Select the imminent operation

Load each contract immediately before the operation it governs:

| Operation | Contract |
| --- | --- |
| Select or stage commit scope | [Scope and staging](attribution/staging.md) |
| Draft, validate, or finalize a commit message; decide tool/assistant mentions in PRs, releases, changelogs, or issues | [Message and emoji](attribution/message.md) |
| Resolve commit author/committer identity or signing; evaluate whether hosted integration preserves them | [Identity and signing](attribution/identity.md) |

A complete local commit loads all three in that order. Load only identity/signing for an integration that creates no local commit or message. Re-evaluate before each later operation; a planned commit does not preload a later contract.
