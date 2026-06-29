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

`make link` is not required — nothing is symlinked.

## Restore (new Mac or wipe)

1. Install Canary (`make brew` or MAS).
2. Restore `~/.secrets/` from the vault (`rsync` from mounted snapshot).
3. **Quit Canary Mail.**
4. `make restore-canary`
5. Open Canary; re-authenticate any account that prompts.

Alternative: [Canary Cross-Device Sync](https://canarymail.io/help/how-to-use-cross-device-sync-macos) (QR) — vendor cloud, not dotfiles.

## Public repo / split

Do not copy Canary data into git. Vault only (PII + OAuth).
