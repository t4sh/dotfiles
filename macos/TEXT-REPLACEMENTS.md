# Text Replacements backup

`make backup` (or `make backup-text-replacements`) exports active replacements
from the live macOS KeyboardServices database into:

`~/.secrets/apps/text-replacements/Text Substitutions.plist`

Capture is automatic, without per-entry prompts. Replacement text stays outside
Git. Run `make secrets-backup` afterward to include it in the encrypted vault
through the existing `~/.secrets` manifest entry.

The export includes committed SQLite WAL changes, excludes deleted entries and
cloud metadata, and atomically replaces the previous plist only after successful
validation. A missing database retains the previous backup; a malformed database
or invalid entry fails capture. An empty active list produces an empty plist.

## Restore

Open System Settings → Keyboard → Text Replacements. Drag the backed-up plist
into that window and click Done. Verify the entries there and try a replacement
in a text field. This follows [Apple's documented import flow](https://support.apple.com/en-gu/guide/mac-help/mchl2a7bd795/mac).
Restore is manual; the backup does not overwrite the live database or iCloud state.

Screenshot keyboard shortcuts are already captured automatically by the
`com.apple.symbolichotkeys` row in `apps.tsv`, into `macos/symbolichotkeys.plist`.
