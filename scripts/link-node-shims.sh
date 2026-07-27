#!/usr/bin/env bash
# Create/repair the node-stable + npx-stable shims that the agent environment
# (~/.agents/rules/22-environment.md) and the sanitize/audit/doctor scripts
# depend on. Idempotent: re-run to converge the shims onto the .node-version
# pin — e.g. after nvm upgrades past the pinned release and the old symlink
# dangles. Single source of truth for the shims (install.sh + `make shims`).
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
NODE_PINNED="$(tr -d '[:space:]' < "$DOTFILES/.node-version")"
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

NVM_SH="${HOMEBREW_PREFIX:-$(brew --prefix 2>/dev/null)}/opt/nvm/nvm.sh"
[ -s "$NVM_SH" ] || { echo "nvm.sh not found: $NVM_SH — run: make brew" >&2; exit 1; }
# shellcheck disable=SC1090
\. "$NVM_SH"

NODE_RESOLVED="$(nvm version "$NODE_PINNED")"
[ "$NODE_RESOLVED" != "N/A" ] || {
    echo "pinned Node not installed: $NODE_PINNED — run: nvm install $NODE_PINNED" >&2
    exit 1
}

NODE_BIN="$NVM_DIR/versions/node/$NODE_RESOLVED/bin"
[ -x "$NODE_BIN/node" ] || { echo "node binary missing under $NODE_BIN" >&2; exit 1; }

mkdir -p "$HOME/.local/bin"
ln -sf "$NODE_BIN/node" "$HOME/.local/bin/node-stable"
ln -sf "$NODE_BIN/npx" "$HOME/.local/bin/npx-stable"
echo "  ✓ node-stable / npx-stable → $NODE_RESOLVED"
