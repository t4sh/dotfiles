#!/usr/bin/env bash
# Copy the local vault password to the clipboard without printing it.
set -euo pipefail

KC_SERVICE="DotfilesSecretsVault"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

pass="$(security find-generic-password -s "$KC_SERVICE" -a "$USER" -w 2>/dev/null)" || {
  echo "vault password not found in the local login Keychain: $KC_SERVICE" >&2
  exit 1
}
[[ -n "$pass" ]] || {
  echo "vault password is empty: $KC_SERVICE" >&2
  exit 1
}
generation="$(printf '%s' "$pass" | osascript -l JavaScript "$SCRIPT_DIR/secret-clipboard.js" copy)" || {
  unset pass
  echo "could not copy vault password" >&2
  exit 1
}
unset pass
[[ "$generation" =~ ^[0-9]+$ ]] || {
  echo "clipboard did not return a valid generation" >&2
  exit 1
}
(
  if ! osascript -l JavaScript "$SCRIPT_DIR/secret-clipboard.js" expire "$generation" \
      </dev/null >/dev/null 2>&1; then
    echo "automatic clipboard expiry failed; clear the clipboard manually" >&2
  fi
) &
echo "vault password → clipboard (best-effort clear scheduled in 30 seconds if unchanged)"
