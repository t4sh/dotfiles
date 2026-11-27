## Creating PRs/MRs or editing their titles

Apply to CLI, API/connector, browser, and app UI operations, including drafts and PR-only work.

1. Load `02-attribution.md` and its message/emoji contract before preparing the title.
2. Validate the exact outgoing title against that contract before every creation or title edit. Supply the validated title explicitly; review generated or prefilled titles before submitting.
3. After each write, read the saved title from the provider and compare it exactly with the validated title, then recheck the contract. On GitHub, use `gh pr view <PR> --json title --jq .title` or an equivalent provider read. A successful write response alone is insufficient.
4. Correct any mismatch and repeat verification within the authorized operation. Report unresolved mismatches, failed corrections, or unavailable readback as incomplete title verification.
