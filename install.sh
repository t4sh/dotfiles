#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR" && pwd -P)}"

echo "╔══════════════════════════════════════╗"
echo "║      Mac Bootstrap — dotfiles        ║"
echo "╚══════════════════════════════════════╝"
echo ""

# 1. Xcode CLI tools
if ! xcode-select -p &>/dev/null; then
    echo "→ Installing Xcode Command Line Tools..."
    xcode-select --install
    echo "  Press any key after Xcode CLI tools finish installing."
    read -r -n 1 -s
else
    echo "✓ Xcode CLI tools already installed"
fi

# 2. Homebrew
if ! command -v brew &>/dev/null; then
    echo "→ Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
else
    echo "✓ Homebrew already installed"
fi

# 3. Symlinks
echo ""
echo "→ Creating symlinks..."
bash "$DOTFILES/scripts/link.sh"

# 4. Brew bundle
echo ""
echo "→ Installing packages from Brewfile..."
echo "  (This will take a while — formulae, casks, fonts, App Store apps, VS Code extensions)"
brew bundle --file="$DOTFILES/Brewfile"

# 5. Default shell
if [ "$SHELL" != "/bin/zsh" ]; then
    echo "→ Setting zsh as default shell..."
    chsh -s /bin/zsh
else
    echo "✓ zsh is already default shell"
fi

# 6. NVM + Node
echo ""
echo "→ Setting up NVM and Node..."
NODE_PINNED="$(tr -d '[:space:]' < "$DOTFILES/.node-version")"
export NVM_DIR="$HOME/.nvm"
NVM_SH="${HOMEBREW_PREFIX:-$(brew --prefix 2>/dev/null)}/opt/nvm/nvm.sh"
[ -s "$NVM_SH" ] || { echo "nvm.sh not found: $NVM_SH" >&2; exit 1; }
# shellcheck disable=SC1090
\. "$NVM_SH"
nvm install "$NODE_PINNED"
NODE_RESOLVED="$(nvm version "$NODE_PINNED")"
[ "$NODE_RESOLVED" != "N/A" ] || { echo "Node install failed: $NODE_PINNED" >&2; exit 1; }

# node-stable / npx-stable shims — required by ~/.agents/rules/22-environment.md
# (agents invoke node through these, independent of nvm's per-dir switching).
mkdir -p "$HOME/.local/bin"
ln -sf "$NVM_DIR/versions/node/$NODE_RESOLVED/bin/node" "$HOME/.local/bin/node-stable"
ln -sf "$NVM_DIR/versions/node/$NODE_RESOLVED/bin/npx" "$HOME/.local/bin/npx-stable"

# 7. App preferences — delegated to scripts/restore-apps.sh (single source of
#    truth, shared with `make restore-apps` / `make all`).
bash "$DOTFILES/scripts/restore-apps.sh"

# Terminal.app — install.sh is safe to quit Terminal here (it's a one-time
# bootstrap and you're likely running it from Terminal anyway). Ongoing
# maintenance uses `make terminal` from a non-Terminal shell.
if [ -f "$DOTFILES/apps/terminal/terminal.plist" ]; then
    osascript -e 'tell application "Terminal" to quit' 2>/dev/null || true
    defaults import com.apple.Terminal "$DOTFILES/apps/terminal/terminal.plist" && \
        echo "  ✓ Terminal.app (reopen Terminal to see profiles)"
fi

# 8. Automator Services
echo ""
echo "→ Installing Automator services..."
mkdir -p "$HOME/Library/Services"
cp -R "$DOTFILES/services/"*.workflow "$HOME/Library/Services/" 2>/dev/null && \
    echo "  ✓ Automator services installed" || \
    echo "  - No services to install"

# 9. macOS defaults
echo ""
read -p "→ Run macOS system preferences setup? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    bash "$DOTFILES/macos/defaults.sh"
fi

# 10. Dock layout
read -p "→ Restore Dock layout? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    bash "$DOTFILES/macos/dock.sh"
fi

# 11. SSH key → GitHub
read -p "→ Generate SSH key and register with GitHub? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    bash "$DOTFILES/scripts/ssh-setup.sh"
fi

echo ""
echo "→ Installing git hooks..."
make -C "$DOTFILES" hooks

echo ""
echo "╔══════════════════════════════════════╗"
echo "║          Bootstrap Complete          ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "Manual steps remaining:"
echo "  1. Sign into iCloud & App Store (and iCloud Keychain)"
echo "  2. Restore ~/.secrets from your DotfilesSecrets.sparseimage"
echo "     → fetch the sparseimage from your backup destination"
echo "     → double-click → paste passphrase from 'DotfilesSecretsVault' in Keychain Access"
echo "     → sudo rsync -aL /Volumes/DotfilesSecrets/<latest-stamp>/ /"
echo "     → make link   (wire ~/.secrets consumer symlinks)"
echo "     → echo \"<destination>\" > ~/.dotfiles-local/backup.destination"
echo "  3. Canary Mail (if used): quit app, then make restore-canary"
echo "  4. Raycast: import config from ~/.secrets/apps/raycast/ (Settings → Advanced → Import)"
echo "     then import extensions if needed; Transmit: import from ~/.secrets/apps/transmit/"
echo "  5. Sign into apps: VS Code sync, Figma, etc."
echo "  6. Set default browser"
echo "  7. Apply default app policy: cd ~/.dotfiles && make default-apps"
echo "  8. Optional: open Hammerspoon once and allow Accessibility permissions"
echo "  9. Run bootstrap preflight checks: cd ~/.dotfiles && make doctor"
echo " 10. Install global agent skills: cd ~/.dotfiles && make skills"
echo "     (needs vault restore + gh auth for skill sources that need GitHub auth)"
echo ""
