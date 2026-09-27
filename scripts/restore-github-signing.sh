#!/usr/bin/env bash
# Restore only GitHub's public web-commit verifier; never copy private GPG state.
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || { echo 'This is a macOS workflow.' >&2; exit 2; }
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
GPG="$(command -v gpg || true)"
[[ -n "$GPG" ]] || { echo 'GPG is required; run make brew first.' >&2; exit 1; }
KEY="$DOTFILES/git/keys/github-web-flow.asc"
FINGERPRINT=968479A1AFF927E37D1A566BB5690EEEBB952194
# Reject an unexpected replacement or additional primary key before importing.
actual="$("$GPG" --batch --with-colons --show-keys "$KEY" | awk -F: '
  $1 == "pub" { primary=1; next }
  primary && $1 == "fpr" { print $10; primary=0 }
')"
[[ "$actual" == "$FINGERPRINT" ]] || { echo 'Unexpected GitHub signing key.' >&2; exit 1; }
"$GPG" --batch --import "$KEY"
# Explicit local trust anchor, authenticated against https://github.com/web-flow.gpg.
printf '%s:6:\n' "$FINGERPRINT" | "$GPG" --batch --import-ownertrust
# Resolve the installed executable on this Mac (Intel or Apple Silicon).
git config --global gpg.program "$GPG"
echo '  ✓ GitHub public signing key, trust and GPG executable restored'
