#!/usr/bin/env bash
# Windows uses native entry points; reject before any Unix-path mutation.
case "${OS:-}:$(uname -s)" in
  Windows_NT:*|*:MINGW*|*:MSYS*) echo 'This is a macOS workflow. On Windows run bin/dot.cmd help.' >&2; exit 2 ;;
esac
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
export DOTFILES="$SCRIPT_DIR"
BOOTSTRAP_SMOKE="${DOTFILES_BOOTSTRAP_SMOKE:-0}"

if [[ "$BOOTSTRAP_SMOKE" == "1" && "${CI:-}" != "true" ]]; then
    echo "DOTFILES_BOOTSTRAP_SMOKE=1 is reserved for disposable CI runners." >&2
    exit 1
fi

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
    echo ""
    if ! xcode-select -p &>/dev/null; then
        echo "Xcode Command Line Tools installation incomplete." >&2
        echo "Finish or retry 'xcode-select --install', then rerun ./install.sh." >&2
        exit 1
    fi
    echo "✓ Xcode CLI tools installed"
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

# 4. Brew core first; optional GUI/editor inventory is a resumable phase.
echo ""
echo "→ Installing bootstrap formulae..."
make -C "$DOTFILES" brew-core

BREW_APPS_FAILED=0
if [[ "$BOOTSTRAP_SMOKE" == "1" ]]; then
    echo "  - disposable core smoke: GUI apps, fonts, and editor extensions deferred"
else
    echo "→ Installing GUI apps, fonts, and editor extensions..."
    if ! make -C "$DOTFILES" brew-apps; then
        BREW_APPS_FAILED=1
        echo "  ⚠ optional app phase incomplete; bootstrap will continue"
        echo "    retry later with: make brew-apps"
    fi
fi

# 5. Default shell
if [[ "$BOOTSTRAP_SMOKE" == "1" ]]; then
    echo "  - disposable core smoke: default-shell mutation deferred"
elif [ "$SHELL" != "/bin/zsh" ]; then
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

if [[ "$BOOTSTRAP_SMOKE" == "1" ]]; then
    echo ""
    echo "→ Exercising disposable service and hook installation..."
    make -C "$DOTFILES" services
    make -C "$DOTFILES" hooks
    make -C "$DOTFILES" rules-audit
    make -C "$DOTFILES" skills
    echo ""
    echo "Disposable macOS core bootstrap smoke complete."
    echo "GUI casks, app preference restore, Dock, system defaults, MAS, and vault recovery remain outside hosted-runner coverage."
    exit 0
fi

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
    make -C "$DOTFILES" macos
else
    echo "  - macOS policy deferred; run: make macos"
fi

echo ""
echo "╔══════════════════════════════════════╗"
echo "║          Bootstrap Complete          ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "Manual steps remaining:"
echo "  1. Sign into the App Store → make brew-mas"
echo "  2. Restore ~/.secrets from a completed DotfilesSecrets recovery DMG set"
echo "     → configure backup.destination (or DOTFILES_BACKUP_DEST); run: make secrets-mount"
echo "     → passphrase from independent password manager; optionally Remember in Finder"
echo "     → make secrets-restore       # read-only validation"
echo "     → make secrets-restore-apply # explicit transactional ~/.secrets restore"
echo "     → make secrets-pass-import"
echo "     → echo \"<destination>\" > ~/.dotfiles-local/backup.destination   # optional"
echo "  3. make post-vault          # link, ssh-setup, Shottr/Canary if present, restore-apps"
echo "  4. Finish the short GUI list printed by make post-vault"
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

if (( BREW_APPS_FAILED )); then
    echo ""
    echo "Bootstrap completed with an incomplete optional app phase."
    echo "Retry: make brew-apps"
    exit 1
fi
