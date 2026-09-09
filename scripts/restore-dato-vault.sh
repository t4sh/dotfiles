#!/usr/bin/env bash
# Restore the full primary domain only after macOS has created Dato's container.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
DOMAIN=com.sindresorhus.Dato
SOURCE="$HOME/.secrets/apps/dato/$DOMAIN.plist"
DEST="$HOME/Library/Containers/$DOMAIN/Data/Library/Preferences/$DOMAIN.plist"
[[ -f "$SOURCE" ]] || { echo "Dato vault copy missing; run make backup-dato on the configured Mac." >&2; exit 1; }
[[ -d "$(dirname "$DEST")" ]] || { echo "Launch Dato once, then run make restore-dato." >&2; exit 1; }
plutil -lint "$SOURCE" >/dev/null
# shellcheck source=scripts/lib/running-app-gate.sh
source "$DOTFILES/scripts/lib/running-app-gate.sh"
trap restore_reopen_apps EXIT
restore_running_app_gate "Dato:Dato"
defaults import "${DEST%.plist}" "$SOURCE"
echo "Full Dato preferences restored; macOS permissions and login registration remain separate."
