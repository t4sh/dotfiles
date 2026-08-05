# Canary Mail — vault-only config

Canary is installed via `Brewfile` (`mas "Canary Mail"`). **No prefs live in this repo.**

Account and UI state sit in the App Store sandbox:

```text
~/Library/Containers/io.canarymail.mac/Data/Library/
├── Preferences/io.canarymail.mac.plist   # UI + account list (emails)
└── Application Support/CanaryDB/
    ├── *.realm                           # accounts, OAuth, PGP (~5MB)
    └── emls2.ldb/                        # mail cache (~1.6GB) — NOT backed up
```

## Backup

```bash
make backup-canary    # → ~/.secrets/apps/canary-mail/
make secrets-backup   # encrypt ~/.secrets/ into the sparseimage vault
```

`make backup-canary` fails closed if process state cannot be determined, Canary is still running, or CanaryDB has not initialized. It then accepts basename-only entries from `config/canary-managed-realms.tsv`, creates the snapshot with private permissions, and atomically publishes a complete preferences-plus-realms envelope. `make link` is not required — nothing is symlinked.

## Restore (new Mac or wipe)

1. Install Canary (`make brew` or MAS).
2. Mount the vault, then run `make secrets-restore` and `make secrets-restore-apply`.
3. Run `make secrets-pass-import`, then `make post-vault`; it restores Canary automatically when the complete payload is present.
4. Re-authenticate any account that prompts.

Alternative: [Canary Cross-Device Sync](https://canarymail.io/help/how-to-use-cross-device-sync-macos) (QR) — vendor cloud, not dotfiles.

## Public repo / split

Do not copy Canary data into git. Vault only (PII + OAuth).
