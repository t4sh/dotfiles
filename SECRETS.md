# Mac recovery vault

Keep credentials and licensed exports under `~/.secrets/`, outside Git. Configure
the local backup manifest with `make secrets-manifest`, review its paths, and
select a destination folder when first running `make secrets-backup`.

The default backup updates `DotfilesSecrets.dmg`, an AES-256 encrypted APFS
UDRW image, retaining five verified dated snapshots. Each run edits a local
encrypted copy, verifies copied content and every retained snapshot, ejects and
reopens the copy read-only, then publishes the closed image and completion
sidecars. Existing baselines under `baselines/` are verified and never pruned.
Missing sources or damaged receipts stop publication and preserve the destination.

Before first backup, store the vault passphrase in an independently synchronized
password manager and verify recovery from another device. The login Keychain
item alone is not a recovery copy. `make secrets-pass` copies the local password;
`make secrets-pass-import` imports a recovered password into the local Keychain.
Only the operator can confirm that independent recovery storage is ready.

| Command | Purpose |
| --- | --- |
| `make secrets-backup` | Update the persistent image; default retention is five snapshots |
| `make secrets-backup-portable` | Publish a separate immutable compressed recovery DMG |
| `make secrets-backup-legacy` | Append to the preserved legacy sparseimage |
| `make secrets-mount` | Check image sidecars and open the persistent image; fall back to a completed portable image when absent |
| `make secrets-restore` | Check the newest mounted snapshot without restoring |
| `make secrets-restore-apply` | Explicitly replace the local secrets tree from that snapshot |

Eject the persistent vault before backup and leave it closed until publication
finishes. The image has a fixed default capacity of `4g`; `DOTFILES_VAULT_SIZE`
sets the initial capacity and `DOTFILES_BACKUP_KEEP` sets retention. Allow disk
space for the destination, working copy and publication copy. A full image stops
without deleting retained recovery history merely to attempt a new snapshot.

Finder's writable mounts can change filesystem metadata and invalidate the outer
checksum. `make secrets-mount` intentionally rejects mismatched sidecars;
double-click browsing remains available. The next backup can recover a valid
image by checking all internal receipts before refreshing the sidecars. Receipts
ignore `.DS_Store` metadata, but reject other added, changed or removed payload
files. The image, JSON metadata and checksum are published sequentially; cloud
upload completion is controlled by the sync application, not by this script.

On a replacement Mac, recover the independently stored password and set
`DOTFILES_BACKUP_DEST` to the folder holding the image and its sidecars. Run
`make secrets-mount`, unlock it, then `make secrets-restore` before choosing
`make secrets-restore-apply`. Restore checks available receipts and stages the
canonical payload before replacing `~/.secrets/`. Legacy snapshots without
receipts remain supported. Other absolute-path manifest mirrors require manual
recovery; they are not automatically restored over application data.

The Python fixtures use dummy files and never open a live vault. Native disk-image
compatibility, Finder auto-unlock, cloud synchronization and recovery on another
machine require separate operator verification. Windows uses its independent
`.tar.age` workflow described in [WINDOWS.md](WINDOWS.md).
