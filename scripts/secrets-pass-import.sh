#!/usr/bin/env bash
# Import a recovered vault password into the local login Keychain without echoing it.
set -euo pipefail

KC_SERVICE="DotfilesSecretsVault"

[[ -t 0 ]] || {
  echo "interactive terminal required to import the recovered vault password" >&2
  exit 1
}
# A bare final -w uses security's native prompt; the password never becomes a
# process argument or a shell variable. Cancellation propagates as a failure.
security add-generic-password \
  -a "$USER" -s "$KC_SERVICE" \
  -D "disk image password" \
  -l "Dotfiles Secrets Vault" \
  -U -w
echo "recovered vault password saved to the local login Keychain"
