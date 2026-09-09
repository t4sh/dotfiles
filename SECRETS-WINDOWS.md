# Windows encrypted recovery

Windows uses authenticated `.tar.age` archives. macOS uses its existing encrypted
APFS DMG workflow. These are separate containers; validate platform compatibility
before restoring application data across operating systems.

The public Windows backup manifest captures `~/.secrets` only. Put private exports
there explicitly; editor capture does not populate it. Keys, local backup state,
and generated archives stay outside Git.

## First backup

From the checkout in standard PowerShell 7.4+:

```powershell
bin\dot.cmd secrets-backup -Action InitializeKey -Apply
```

Independently save the generated recovery key from
`~/.secrets-keys/windows-backup.agekey` in a secure recovery location. The key is
not included in the archive. After confirming that independent copy:

```powershell
bin\dot.cmd secrets-backup -Action ConfirmRecovery -Apply
bin\dot.cmd secrets-backup -Apply -Destination 'D:\Backups'
bin\dot.cmd secrets-backup -Action Check -Archive 'D:\Backups\backup.tar.age' -Apply
```

Replace the example archive name with the actual completed backup. Omitting
`-Apply` previews operations. Subsequent interactive backups can reuse the saved
destination; unattended backups require `-NonInteractive` and an explicit or
saved destination. Only encrypted output may use a supported cloud directory.
Keys and plaintext staging require ordinary local paths with restricted access.

## Inspect recovery

```powershell
bin\dot.cmd secrets-open -Archive 'D:\Backups\backup.tar.age' -Apply
bin\dot.cmd secrets-close -View 'C:\path\to\the\opened-view' -Apply
```

Open authenticates the archive and extracts a protected local view. Use the view
path printed by Open when closing it. This does not restore over live files.
Inspect and recover deliberately; automated live restoration is not provided.

`bin\dot.cmd private-snapshot -Apply` is a separate **unencrypted local reference**,
not an encrypted backup. It uses the same source manifest, records checksums and
platform/device paths, and must remain outside repositories and cloud folders.
For validation, pass a disposable `-ProfileRoot` to the underlying recovery
scripts, use dummy `.secrets` data and a dedicated local destination, and never use
real recovery keys or personal exports as test fixtures.
