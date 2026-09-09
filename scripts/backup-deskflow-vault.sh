#!/usr/bin/env bash
# Capture Deskflow configuration and TLS identity privately, never into git.
set -euo pipefail
umask 077

SOURCE="$HOME/Library/Deskflow"
DEST="$HOME/.secrets/apps/deskflow"
[[ -s "$SOURCE/Deskflow.conf" ]] || { echo "Deskflow configuration missing or empty; previous backup retained." >&2; exit 1; }

mkdir -p "$DEST"
chmod 700 "$HOME/.secrets" "$HOME/.secrets/apps" "$DEST"
STAGE="$(mktemp -d "$DEST/.deskflow.tmp.XXXXXX")"
trap 'rm -rf -- "$STAGE"' EXIT
# A single archive publishes the entire configuration together, including TLS
# identity/trust files, and naturally drops files removed since the last capture.
COPYFILE_DISABLE=1 tar -czf "$STAGE/Deskflow.tar.gz" -C "$HOME/Library" Deskflow
tar -tzf "$STAGE/Deskflow.tar.gz" >/dev/null
chmod 600 "$STAGE/Deskflow.tar.gz"
mv "$STAGE/Deskflow.tar.gz" "$DEST/Deskflow.tar.gz"
echo "Deskflow configuration and TLS files captured in ~/.secrets/apps/deskflow/Deskflow.tar.gz. Run make secrets-backup to encrypt them."
