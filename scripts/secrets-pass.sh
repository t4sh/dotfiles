#!/usr/bin/env bash
# Copy the local vault password to the clipboard without printing it.
set -euo pipefail

KC_SERVICE="DotfilesSecretsVault"

pass="$(security find-generic-password -s "$KC_SERVICE" -a "$USER" -w 2>/dev/null)" || {
  echo "vault password not found in the local login Keychain: $KC_SERVICE" >&2
  exit 1
}
[[ -n "$pass" ]] || {
  echo "vault password is empty: $KC_SERVICE" >&2
  exit 1
}
printf '%s' "$pass" | pbcopy
unset pass
echo "vault password → clipboard"
