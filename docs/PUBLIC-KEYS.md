# Public verification keys

Verification material is public; authentication and signing still require a
private key. The following vendor keys identify GitHub, not the dotfiles owner.
Checked against GitHub's published material on 2026-10-10. No example installs
keys or changes a trust database, SSH configuration or signing identity.

| File | Owner / identity | Purpose |
| --- | --- | --- |
| [allowed_signers](../ssh/allowed_signers) | Repository owner's noreply principal; see [fork guide](FORKING.md) | Verify the owner's SSH-signed Git commits |
| [github-host-keys.pub](../ssh/github-host-keys.pub) | GitHub SSH service at `github.com` | Compare host-key fingerprints before trusting a connection |
| [github-web-flow.asc](../git/keys/github-web-flow.asc) | `GitHub <noreply@github.com>` | Existing verifier for GitHub web commits |
| [github-web-flow-legacy.asc](../git/keys/github-web-flow-legacy.asc) | `GitHub (web-flow commit signing) <noreply@github.com>` | Historical GitHub web-commit verifier; expired 2024-01-16 |

## SSH host fingerprints

The `.pub` file contains three public key lines, not a captured `known_hosts`
inventory. They were retrieved from [GitHub's Meta API](https://api.github.com/meta)
and their derived SHA256 values match its fingerprint fields and
[GitHub's SSH fingerprint documentation](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints).

| Algorithm | SHA256 fingerprint |
| --- | --- |
| ED25519 | `SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU` |
| ECDSA | `SHA256:p2QAMXNIC1TJYWeIOttrVc98/R1BUFWu3/LiyKgUfQM` |
| RSA | `SHA256:uNiVztksCsDhcc0u9e8BujQXVUpKZIDTMczCvj3tD2s` |

Offline inspection from the repository root:

```sh
ssh-keygen -lf ssh/github-host-keys.pub -E sha256
```

A host key authenticates the server; it does not verify Git commit authors or
log you in. This snapshot does not override a host-key mismatch. Before manually
trusting a host, check GitHub's current documentation through an independently
trusted HTTPS connection, compare the fingerprint actually offered, and stop on
an unexplained mismatch. Do not trust raw `ssh-keyscan` output by itself or disable
host checking. For a future refresh, retrieve current vendor material, compare
all fingerprints, review the diff and update this table and date together.

## GPG web-commit fingerprints

| Verifier | Primary fingerprint | Status |
| --- | --- | --- |
| Existing GitHub key | `968479A1AFF927E37D1A566BB5690EEEBB952194` | Matches the modern key in GitHub's published bundle |
| Additional historical key | `5DE3E0509C47EA3CF04A42D34AEE18F83AFDEB23` | Expired; historical inspection only |

Both public certificates and user IDs were checked against
[GitHub's web-flow bundle](https://github.com/web-flow.gpg). The historical key
was exported individually from that bundle in a disposable GPG home. It is not
added to the existing restore helper or granted ownertrust. Key expiry and
signature time must be considered when interpreting a historical local result;
a GitHub persistent Verified record and a current local trust result can differ.
See [GitHub signature verification](https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification).

To inspect without importing into your own keyring, use a disposable GPG home
(POSIX shell; GPG must already be installed):

```sh
task_gpg_dir=$(mktemp -d)
gpg --homedir "$task_gpg_dir" --batch --with-colons --show-keys git/keys/github-web-flow.asc
gpg --homedir "$task_gpg_dir" --batch --with-colons --show-keys git/keys/github-web-flow-legacy.asc
```

This checks certificate metadata, not a particular commit's signature. Verification
requires the signed artifact as well as the expected signer; possessing a public
certificate does not establish trust in every signature.

## Additional personal keys

A deliberate public key may be included after reviewing its owner/principal,
fingerprint, purpose, UID/comment metadata and intended account linkage. A GPG
public export can expose user IDs and emails; SSH comments can expose host names.
Keep private keys, revocation secrets, full keyring exports, authentication tokens
and real host inventories out. Current additions select only vendor verification
material; they do not broaden the owner's personal identity baseline.
