#!/usr/bin/env bash
# Windows uses native entry points; reject before any Unix-path mutation.
case "${OS:-}:$(uname -s)" in
  Windows_NT:*|*:MINGW*|*:MSYS*) echo 'This is a macOS workflow. On Windows run bin/dot.cmd help.' >&2; exit 2 ;;
esac
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
export DOTFILES="$SCRIPT_DIR"
BOOTSTRAP_SMOKE="${DOTFILES_BOOTSTRAP_SMOKE:-0}"
export APP_GROUPS="${APP_GROUPS-all}"
COMPLETED_STAGES=()
DEFERRED_STAGES=()
CURRENT_STAGE='Xcode Command Line Tools'
CURRENT_RETRY='xcode-select --install'
BREW_APPS_FAILED=0
REPORT_PRINTED=0
TERMINAL_PENDING=0

bootstrap_report() {
    local status="$1" item
    echo ''
    if (( status != 0 || BREW_APPS_FAILED != 0 )); then
        echo 'Bootstrap incomplete — completed stages are retained.'
    elif (( TERMINAL_PENDING )); then
        echo 'Bootstrap progress — optional Terminal import is still pending.'
    elif [[ "$BOOTSTRAP_SMOKE" == 1 ]]; then
        echo 'Disposable core stages finished; full-machine setup remains unverified.'
    else
        echo 'Bootstrap stages finished — manual steps and verification remain.'
    fi
    for item in ${COMPLETED_STAGES[@]+"${COMPLETED_STAGES[@]}"}; do echo "  DONE     $item"; done
    if (( BREW_APPS_FAILED )); then
        echo "  FAILED   Selected apps ($APP_GROUPS). Retry: make brew-apps APP_GROUPS=$APP_GROUPS"
    fi
    if (( status != 0 )) && [[ -n "$CURRENT_STAGE" ]]; then
        echo "  STOPPED  $CURRENT_STAGE. Next: $CURRENT_RETRY"
    fi
    for item in ${DEFERRED_STAGES[@]+"${DEFERRED_STAGES[@]}"}; do echo "  DEFERRED $item"; done
    if [[ "$BOOTSTRAP_SMOKE" != 1 ]]; then
        echo '  MANUAL   Sign into the App Store → make brew-mas'
        echo '  MANUAL   Recover ~/.secrets using README recovery instructions; keep the independent recovery password available'
        echo '           make secrets-restore (validate) → make secrets-restore-apply (explicit restore) → make secrets-pass-import'
        echo '  MANUAL   make keychain-list → recover tool items separately → make keychain-check'
        echo '  MANUAL   gh auth login -h github.com → make post-vault; follow its GUI checklist'
        echo '  MANUAL   Default-app choices remain separate → make default-apps-check'
        echo "  CHECK    make setup-status APP_GROUPS=$APP_GROUPS (read-only; does not certify sign-ins)"
        echo '  CHECK    make verify-bootstrap after recovery (strict full-inventory acceptance)'
    fi
}

bootstrap_exit() {
    local status=$?
    if (( REPORT_PRINTED == 0 )); then bootstrap_report "$status"; fi
    if (( REPORT_PRINTED && status != 0 )) && [[ -n "$CURRENT_STAGE" ]]; then
        echo "  STOPPED  $CURRENT_STAGE. Next: $CURRENT_RETRY"
    fi
    return "$status"
}
trap bootstrap_exit EXIT

prompt_yes_no() {
    local prompt_text=$1
    REPLY=""
    if [[ ! -t 0 ]]; then
        echo "  - no interactive terminal; skipped: $prompt_text" >&2
        return 1
    fi
    if ! read -r -p "$prompt_text" -n 1 REPLY; then
        echo "" >&2
        echo "  - no response received; skipped: $prompt_text" >&2
        REPLY=""
        return 1
    fi
    echo ""
}

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
    if ! read -r -n 1 -s; then
        echo "No interactive response received. Finish Xcode CLI tools installation, then rerun ./install.sh." >&2
        exit 1
    fi
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
COMPLETED_STAGES+=('Xcode Command Line Tools')

# 2. Homebrew
CURRENT_STAGE='Homebrew'; CURRENT_RETRY='bash install.sh'
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
COMPLETED_STAGES+=('Homebrew')

# Validate selection before linking or installing declared packages.
CURRENT_STAGE='App group selection'; CURRENT_RETRY='make app-groups'
if command -v python3 >/dev/null 2>&1; then
    python3 "$DOTFILES/scripts/app_groups.py" list
else
    echo 'App group validation deferred until core tools provide Python; no apps will install before validation.'
fi

# 3. Symlinks
echo ""
echo "→ Creating symlinks..."
CURRENT_STAGE='Configuration links'; CURRENT_RETRY='make link'
bash "$DOTFILES/scripts/link.sh"
COMPLETED_STAGES+=('Configuration link phase (missing pre-vault sources may be deferred)')

# 4. Brew core first; optional GUI/editor inventory is a resumable phase.
echo ""
echo "→ Installing bootstrap formulae..."
CURRENT_STAGE='Core tools'; CURRENT_RETRY='make brew-core'
make -C "$DOTFILES" brew-core
COMPLETED_STAGES+=('Core tools')

CURRENT_STAGE='Selected apps'; CURRENT_RETRY="make brew-apps APP_GROUPS=$APP_GROUPS"
if [[ "$BOOTSTRAP_SMOKE" == "1" ]]; then
    echo "  - disposable core smoke: GUI apps, fonts, and editor extensions deferred"
    DEFERRED_STAGES+=('GUI apps, fonts and editor extensions (disposable core smoke)')
else
    echo "→ Installing GUI apps, fonts, and editor extensions..."
    if ! make -C "$DOTFILES" brew-apps; then
        BREW_APPS_FAILED=1
        echo "  ⚠ optional app phase incomplete; bootstrap will continue"
        echo "    retry later with: make brew-apps"
    else
        if [[ "$APP_GROUPS" == none ]]; then
            DEFERRED_STAGES+=('All app groups → make brew-apps APP_GROUPS=all')
        else
            COMPLETED_STAGES+=("Selected app phase ($APP_GROUPS)")
            [[ "$APP_GROUPS" == all ]] || DEFERRED_STAGES+=('Unselected app groups → make app-groups')
        fi
    fi
fi

# 5. Default shell
CURRENT_STAGE='Default shell'; CURRENT_RETRY='bash install.sh'
if [[ "$BOOTSTRAP_SMOKE" == "1" ]]; then
    echo "  - disposable core smoke: default-shell mutation deferred"
    DEFERRED_STAGES+=('Default shell (disposable core smoke)')
else
    if ! account_shell="$(dscacheutil -q user -a name "$(id -un)" | awk '$1 == "shell:" { print $2; exit }')" || [[ -z "$account_shell" ]]; then
        echo "Could not read the account's default shell" >&2
        exit 1
    fi
    if [[ "$account_shell" != "/bin/zsh" ]]; then
        echo "→ Setting zsh as default shell..."
        chsh -s /bin/zsh
    else
        echo "✓ zsh is already default shell"
    fi
    COMPLETED_STAGES+=('Default-shell phase')
fi

# 6. NVM + Node + npm globals. Brew's npm rows are deliberately deferred until
# the pinned runtime exists so they never land under Homebrew's transient Node.
echo ""
echo "→ Setting up NVM and Node..."
CURRENT_STAGE='Node runtime'; CURRENT_RETRY='make node'
make -C "$DOTFILES" node
COMPLETED_STAGES+=('Pinned Node runtime')
echo "→ Installing npm globals under pinned Node..."
CURRENT_STAGE='npm tools'; CURRENT_RETRY='make brew-npm'
make -C "$DOTFILES" brew-npm
COMPLETED_STAGES+=('npm tools')

# node-stable / npx-stable shims — required by ~/.agents/rules/22-environment.md
# (agents invoke node through these, independent of nvm's per-dir switching).
# Single source of truth: scripts/link-node-shims.sh (also `make shims`).
CURRENT_STAGE='Runtime shims'; CURRENT_RETRY='make shims'
make -C "$DOTFILES" shims
COMPLETED_STAGES+=('Runtime shims')

if [[ "$BOOTSTRAP_SMOKE" == "1" ]]; then
    echo ""
    echo "→ Exercising disposable service and hook installation..."
    CURRENT_STAGE='Disposable service/hook checks'; CURRENT_RETRY='rerun the disposable bootstrap smoke'
    make -C "$DOTFILES" services
    make -C "$DOTFILES" hooks
    make -C "$DOTFILES" rules-audit
    make -C "$DOTFILES" skills
    echo ""
    echo "Disposable macOS core bootstrap smoke complete."
    echo "GUI casks, app preference restore, Dock, system defaults, MAS, and vault recovery remain outside hosted-runner coverage."
    COMPLETED_STAGES+=('Disposable services, hooks, rule and skill checks')
    CURRENT_STAGE=''
    exit 0
fi

CURRENT_STAGE='Impeccable engine'; CURRENT_RETRY='make skills-engine'
make -C "$DOTFILES" skills-engine
COMPLETED_STAGES+=('Impeccable engine')
CURRENT_STAGE='Fluid Functionalism audit dependencies'; CURRENT_RETRY='make skills-browser'
make -C "$DOTFILES" skills-browser
COMPLETED_STAGES+=('Fluid Functionalism audit dependencies')

# 7. Restore portable agent hooks after RTK is installed, then services.
CURRENT_STAGE='Codex RTK hook'; CURRENT_RETRY='make restore-codex-rtk'
make -C "$DOTFILES" restore-codex-rtk
COMPLETED_STAGES+=('Codex RTK hook')
CURRENT_STAGE='Claude RTK hook'; CURRENT_RETRY='make restore-claude-rtk'
make -C "$DOTFILES" restore-claude-rtk
COMPLETED_STAGES+=('Claude RTK hook')
echo ""
echo "→ Installing Automator services..."
CURRENT_STAGE='Automator services'; CURRENT_RETRY='make services'
make -C "$DOTFILES" services
COMPLETED_STAGES+=('Automator services')

# 8. App preferences — delegated to scripts/restore-apps.sh (single source of
#    truth, shared with `make restore-apps` / `make all`).
CURRENT_STAGE='Preference restore'; CURRENT_RETRY='make restore-apps'
if [[ "$APP_GROUPS" == all ]]; then
    bash "$DOTFILES/scripts/restore-apps.sh"
    COMPLETED_STAGES+=('Managed preference restore phase (host-app settings may be deferred)')
else
    DEFERRED_STAGES+=('Aggregate app preferences preserved for partial selection; explicit full restore → make restore-apps')
fi

# 9. Dock layout — before hooks/macos so Ctrl-C during interactive defaults
#    cannot skip Dock (same relative order as `make all`: dock → hooks → macos).
echo ""
CURRENT_STAGE='Dock'; CURRENT_RETRY='make dock'
if prompt_yes_no "→ Restore Dock layout? (y/n) "; then
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    bash "$DOTFILES/macos/dock.sh"
    COMPLETED_STAGES+=('Dock layout')
  else
    DEFERRED_STAGES+=('Dock layout → make dock')
  fi
else
  DEFERRED_STAGES+=('Dock layout → make dock')
fi

# SSH setup is intentionally post-vault. Generating into ~/.secrets before an
# existing vault is restored can create and upload a throwaway key.
echo ""
echo "→ Installing git hooks..."
CURRENT_STAGE='Git hooks'; CURRENT_RETRY='make hooks'
make -C "$DOTFILES" hooks
COMPLETED_STAGES+=('Git hooks')

# 11. macOS defaults last (interactive; matches `make all`).
echo ""
CURRENT_STAGE='macOS policy'; CURRENT_RETRY='make macos'
if prompt_yes_no "→ Run macOS system preferences setup? (y/n) "; then
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    make -C "$DOTFILES" macos
    COMPLETED_STAGES+=('macOS policy phase; verify with make macos-check')
  else
    echo "  - macOS policy deferred; run: make macos"
    DEFERRED_STAGES+=('macOS policy → make macos')
  fi
else
    echo "  - macOS policy deferred; run: make macos"
    DEFERRED_STAGES+=('macOS policy → make macos')
fi

CURRENT_STAGE=''

# Terminal.app profile import quits Terminal.app, so keep it after all bootstrap
# output/prompts. Print a progress report before quitting in case this shell ends;
# only a completed import can appear in the final DONE list.
if [ -f "$DOTFILES/apps/terminal/terminal.plist" ]; then
    if prompt_yes_no "→ Import Terminal.app profiles now? This quits Terminal.app. (y/n) "; then
      if [[ $REPLY =~ ^[Yy]$ ]]; then
        CURRENT_STAGE='Terminal profile import'; CURRENT_RETRY='make terminal from another terminal app'
        TERMINAL_PENDING=1
        bootstrap_report 0
        osascript -e 'tell application "Terminal" to quit' 2>/dev/null || true
        defaults import com.apple.Terminal "$DOTFILES/apps/terminal/terminal.plist"
        echo "  ✓ Terminal.app (reopen Terminal to see profiles)"
        COMPLETED_STAGES+=('Terminal profile import')
        TERMINAL_PENDING=0
        CURRENT_STAGE=''
      else
        echo "  - skipped Terminal.app profiles; run 'make terminal' later from iTerm / Ghostty / VS Code"
        DEFERRED_STAGES+=('Terminal profile import → make terminal from another terminal app')
      fi
    else
      DEFERRED_STAGES+=('Terminal profile import → make terminal from another terminal app')
    fi
fi

bootstrap_report 0
REPORT_PRINTED=1

if (( BREW_APPS_FAILED )); then
    echo ""
    echo "Bootstrap completed with an incomplete optional app phase."
    echo "Retry: make brew-apps"
    exit 1
fi
