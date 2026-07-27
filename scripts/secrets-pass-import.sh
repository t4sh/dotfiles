#!/usr/bin/env bash
# Import a recovered vault password into the local login Keychain without echoing it.
set -euo pipefail

KC_SERVICE="DotfilesSecretsVault"

[[ -t 0 ]] || {
  echo "interactive terminal required to import the recovered vault password" >&2
  exit 1
}
read -r -s -p "Recovered vault password: " pass
echo ""
[[ -n "$pass" ]] || {
  echo "vault password was empty; Keychain was not changed" >&2
  exit 1
}
security add-generic-password \
  -a "$USER" -s "$KC_SERVICE" \
  -D "disk image password" \
  -l "Dotfiles Secrets Vault" \
  -U -w "$pass"
unset pass
echo "recovered vault password saved to the local login Keychain"
