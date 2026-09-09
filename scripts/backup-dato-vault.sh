#!/usr/bin/env bash
# Capture the full primary Dato domain privately; calendar IDs stay out of git.
set -euo pipefail
umask 077

DOMAIN=com.sindresorhus.Dato
SOURCE="$HOME/Library/Containers/$DOMAIN/Data/Library/Preferences/$DOMAIN.plist"
DEST="$HOME/.secrets/apps/dato"
[[ -f "$SOURCE" ]] || { echo "Dato preferences missing; launch and configure Dato first." >&2; exit 1; }

mkdir -p "$DEST"
chmod 700 "$HOME/.secrets" "$HOME/.secrets/apps" "$DEST"
STAGE="$(mktemp -d "$DEST/.dato.tmp.XXXXXX")"
trap 'rm -rf -- "$STAGE"' EXIT
# Read through cfprefsd at the sandbox consumer path, rather than the empty
# non-sandboxed domain. Validate before replacing any previous private copy.
defaults export "${SOURCE%.plist}" "$STAGE/$DOMAIN.plist"
python3 - "$STAGE/$DOMAIN.plist" <<'PY'
import plistlib
import sys
with open(sys.argv[1], 'rb') as handle:
    prefs = plistlib.load(handle)
if not isinstance(prefs, dict) or not prefs:
    raise SystemExit('Dato exported empty preferences; prior backup retained.')
PY
chmod 600 "$STAGE/$DOMAIN.plist"
mv "$STAGE/$DOMAIN.plist" "$DEST/$DOMAIN.plist"
echo "Full Dato preferences captured in ~/.secrets/apps/dato/. Run make secrets-backup to encrypt them."
