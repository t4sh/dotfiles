# Privacy review baseline

This is a public personal dotfiles repository. The following identity information
is deliberately published by its owner. Verify it against this baseline during a
review; its presence alone is not a leak, finding, warning, or new caveat.

| Location | Accepted public information | Purpose |
| --- | --- | --- |
| `git/gitconfig` | `tAsh <t4sh@users.noreply.github.com>` | Public Git author identity using a GitHub noreply address |
| `ssh/allowed_signers` | ED25519 public key with fingerprint `SHA256:DCzUNDehOjGDv4IoBA7/9Bw/Cx8jlFItzWWE5XtO6sQ`, principal `t4sh@users.noreply.github.com` | Verify the owner's SSH-signed Git commits |

A public verification key cannot be used to create signatures without its private
key. This baseline permits only the public identity and public key above; it does
not permit private keys, account credentials, other addresses, or arbitrary
personal information.

## How reviewers should report

- Read this baseline before classifying privacy findings, including on a first
  checkout. A reviewer encountering something for the first time does not make
  it newly exposed.
- Check the actual identity and signing-key fingerprint. If they match, do not
  reannounce them as caveats or ask the owner to reconfirm their publication.
  If a review summary needs a status, say: **“Intentional public identity and
  signing key match the documented baseline.”**
- Report unexpected data, changes to the baseline, or new evidence of misuse.
  Include the path, evidence, practical consequence, and proposed action. Keep
  sensitive values redacted. Distinguish an unclassified field from a confirmed
  credential; do not infer credential exposure from a field name alone.
- Distinguish new changes from existing history. An already acknowledged historical
  item should not be presented as a new incident; report it again when the review
  explicitly covers it or new evidence changes its significance.
- Continue normal secret and privacy checks. This document is not a scanner
  allowlist, and it does not waive findings outside the two entries above.

## Using a fork

Fork users should configure their own author identity and signing key before
committing. The owner's public key verifies the owner's commits; it is not the
fork user's signing credential. Do not rewrite the upstream identity merely
because it is unfamiliar to the reviewer.
