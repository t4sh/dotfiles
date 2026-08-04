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
    BREW_BIN=""
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$candidate" ]; then
            BREW_BIN="$candidate"
            break
        fi
    done
    [ -n "$BREW_BIN" ] || {
        echo "Homebrew installed but brew was not found under /opt/homebrew or /usr/local" >&2
        exit 1
    }
    eval "$("$BREW_BIN" shellenv)"
else
    echo "✓ Homebrew already installed"
fi

# 3. Symlinks
echo ""
echo "→ Creating symlinks..."
bash "$DOTFILES/scripts/link.sh"

# 4. Brew bundle base (npm waits for pinned Node; App Store waits for sign-in)
echo ""
echo "→ Installing Brewfile base packages (excluding npm and App Store apps)..."
echo "  (This will take a while — formulae, casks, fonts, VS Code extensions)"
make -C "$DOTFILES" brew-base

# 5. Default shell
if [ "$SHELL" != "/bin/zsh" ]; then
    echo "→ Setting zsh as default shell..."
    chsh -s /bin/zsh
else
    echo "✓ zsh is already default shell"
fi

# 6. NVM + Node + npm globals. Brew's npm rows are deliberately deferred until
# the pinned runtime exists so they never land under Homebrew's transient Node.
echo ""
echo "→ Setting up NVM and Node..."
make -C "$DOTFILES" node
echo "→ Installing npm globals under pinned Node..."
make -C "$DOTFILES" brew-npm

# node-stable / npx-stable shims — required by ~/.agents/rules/22-environment.md
# (agents invoke node through these, independent of nvm's per-dir switching).
# Single source of truth: scripts/link-node-shims.sh (also `make shims`).
make -C "$DOTFILES" shims

# 7. Automator Services — before restore-apps (same order as `make all`:
#    services → restore-apps → dock → hooks → macos).
echo ""
echo "→ Installing Automator services..."
make -C "$DOTFILES" services

# 8. App preferences — delegated to scripts/restore-apps.sh (single source of
#    truth, shared with `make restore-apps` / `make all`).
bash "$DOTFILES/scripts/restore-apps.sh"

# 9. Dock layout — before hooks/macos so Ctrl-C during interactive defaults
#    cannot skip Dock (same relative order as `make all`: dock → hooks → macos).
echo ""
read -p "→ Restore Dock layout? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    bash "$DOTFILES/macos/dock.sh"
fi

# SSH setup is intentionally post-vault. Generating into ~/.secrets before an
# existing vault is restored can create and upload a throwaway key.
echo ""
echo "→ Installing git hooks..."
make -C "$DOTFILES" hooks

# 11. macOS defaults last (interactive; matches `make all`).
echo ""
read -p "→ Run macOS system preferences setup? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    bash "$DOTFILES/macos/defaults.sh"
fi

echo ""
echo "╔══════════════════════════════════════╗"
echo "║          Bootstrap Complete          ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "Manual steps remaining:"
echo "  1. Sign into the App Store, then install App Store apps:"
echo "     → cd ~/.dotfiles && make brew-mas"
echo "  2. Sign into iCloud and restore ~/.secrets from your DotfilesSecrets.sparseimage"
echo "     → fetch the sparseimage from your backup destination"
echo "     → retrieve the passphrase from your independently synchronized password manager"
echo "     → double-click the image, paste the passphrase, and tick Remember"
echo "     → sudo rsync -aL /Volumes/DotfilesSecrets/<latest-stamp>/ /"
echo "     → make secrets-pass-import"
echo "     → echo \"<destination>\" > ~/.dotfiles-local/backup.destination"
echo "  3. Restore ownership and consumers:"
echo "     → cd ~/.dotfiles && make post-vault"
echo "  4. Launch Dato once (if used), then run make restore-apps again"
echo "  5. Raycast: import config from ~/.secrets/apps/raycast/ (Settings → Advanced → Import)"
echo "     then import extensions if needed; Transmit: import from ~/.secrets/apps/transmit/"
echo "  6. Sign into apps: VS Code sync, Figma, etc."
echo "  7. Set default browser and run: make default-apps"
echo "  8. Open Hammerspoon, enable Launch at Login, and allow Accessibility permissions"
echo "  9. Run bootstrap preflight checks: cd ~/.dotfiles && make doctor"
echo " 12. Install global agent skills: cd ~/.dotfiles && make skills"
echo "     (needs vault restore + gh auth for skill sources that need GitHub auth)"
echo ""

# Terminal.app profile import quits Terminal.app, so keep it after all bootstrap
# output/prompts. Ongoing maintenance uses `make terminal` from a non-Terminal shell.
if [ -f "$DOTFILES/apps/terminal/terminal.plist" ]; then
    read -p "→ Import Terminal.app profiles now? This quits Terminal.app. (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        osascript -e 'tell application "Terminal" to quit' 2>/dev/null || true
        defaults import com.apple.Terminal "$DOTFILES/apps/terminal/terminal.plist" && \
            echo "  ✓ Terminal.app (reopen Terminal to see profiles)"
    else
        echo "  - skipped Terminal.app profiles; run 'make terminal' later from iTerm / Ghostty / VS Code"
    fi
fi
