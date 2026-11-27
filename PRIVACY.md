# Privacy review baseline

This is a public personal dotfiles repository. The following identity information
is deliberately published by its owner. Verify it against this baseline during a
review; its presence alone is not a leak, finding, warning, or new caveat.

| Location | Accepted public information | Purpose |
| --- | --- | --- |
| `git/gitconfig` | `tAsh <t4sh@users.noreply.github.com>` | Public Git author identity using a GitHub noreply address |
| Filesystem paths in configuration, documentation, and history | `t4sh`, `tAsh`, `tash`, and `ash` as username or home-directory components | Owner-approved public name variants; their presence alone is not a privacy finding |
| `ssh/allowed_signers` | ED25519 public key with fingerprint `SHA256:DCzUNDehOjGDv4IoBA7/9Bw/Cx8jlFItzWWE5XtO6sQ`, principal `t4sh@users.noreply.github.com` | Verify the owner's SSH-signed Git commits |
| `ssh/github-host-keys.pub` | GitHub ED25519, ECDSA and RSA host keys; fingerprints in [PUBLIC-KEYS.md](docs/PUBLIC-KEYS.md) | Authenticate the public GitHub SSH service |
| `git/keys/github-web-flow.asc` | GitHub public GPG key `968479A1AFF927E37D1A566BB5690EEEBB952194`, UID `GitHub <noreply@github.com>` | Verify GitHub web commits |
| `git/keys/github-web-flow-legacy.asc` | GitHub historical GPG key `5DE3E0509C47EA3CF04A42D34AEE18F83AFDEB23`, public GitHub noreply UID; expired | Inspect historical GitHub web signatures; no automatic trust |

A public verification key cannot be used to create signatures without its private
key. This baseline permits only the public identity and verification material above; it does
not permit private keys, account credentials, other addresses, or arbitrary
personal information.

Generic home paths such as `~/Projects`, `~/.agents`, and `$HOME/.config` are
acceptable, as are explicit paths such as `/Users/ash/Projects` using the approved
name variants above. Do not scrub these names or flag a path solely because it
contains one of them. This acceptance does not extend to private organization,
client, or project names elsewhere in the path, credentials, or encoded filesystem
bookmarks containing disk identifiers or other machine-specific metadata.

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
  allowlist, and it does not waive findings outside the entries above.

## Using a fork

Fork users should configure their own author identity and signing key before
committing. The owner's public key verifies the owner's commits; it is not the
fork user's signing credential. Do not rewrite the upstream identity merely
because it is unfamiliar to the reviewer.

For setup steps, see the [fork guide](docs/FORKING.md) and [generic SSH example](ssh/config.example). The example contains public service names and a reserved documentation domain; it grants no access and is not installed automatically.

The [optional examples](examples/README.md) contain curated settings and synthetic policy fixtures. They do not authorize publishing live Codex/Hermes profiles, device inventories, real Services captures or additional personal keys.
