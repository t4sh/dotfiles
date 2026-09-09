#!/usr/bin/env bash
# Install and activate the exact Node runtime declared by .node-version.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
NODE_VERSION_FILE="${DOTFILES_NODE_VERSION_FILE:-$DOTFILES/.node-version}"

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[[ -f "$NODE_VERSION_FILE" ]] || die "Node version file not found: $NODE_VERSION_FILE"
NODE_PINNED="$(tr -d '[:space:]' < "$NODE_VERSION_FILE")"
[[ -n "$NODE_PINNED" ]] || die "Node version file is empty: $NODE_VERSION_FILE"

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
NVM_SH="${DOTFILES_NVM_SH:-$(brew --prefix 2>/dev/null)/opt/nvm/nvm.sh}"
[[ -s "$NVM_SH" ]] || die "nvm.sh not found: $NVM_SH (run: make brew-base)"
# shellcheck disable=SC1090
. "$NVM_SH"

printf 'Installing pinned Node %s...\n' "$NODE_PINNED"
nvm install "$NODE_PINNED"
NODE_RESOLVED="$(nvm version "$NODE_PINNED")"
[[ "$NODE_RESOLVED" != "N/A" && -n "$NODE_RESOLVED" ]] || die "Node install failed: $NODE_PINNED"
nvm use --silent "$NODE_PINNED" >/dev/null
printf '  ✓ Node %s active\n' "$NODE_RESOLVED"
