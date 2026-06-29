#!/usr/bin/env bash
# Set only the lock-screen recovery message using the same cache/env contract as
# macos/defaults.sh. Full macOS setup lives in defaults.sh.
set -euo pipefail

CACHE_DIR="$HOME/.dotfiles-local"
CACHE_FILE="$CACHE_DIR/macos-prefs"
# shellcheck source=/dev/null
[ -f "$CACHE_FILE" ] && . "$CACHE_FILE"

RecoveryPhone="${DOTFILES_RECOVERY_PHONE:-${RecoveryPhone:-}}"
RecoveryEmail="${DOTFILES_RECOVERY_EMAIL:-${RecoveryEmail:-}}"

if [ -z "$RecoveryPhone" ] || [ -z "$RecoveryEmail" ]; then
    echo ":::::: Lock-screen recovery info — one-time setup (values will be cached) ::::::"
    [ -z "$RecoveryPhone" ] && read -r -p ':::::: Recovery Phone at LockScreen: ' RecoveryPhone
    [ -z "$RecoveryEmail" ] && read -r -p ':::::: Recovery Email at LockScreen: ' RecoveryEmail
    mkdir -p "$CACHE_DIR"
    {
        echo "# Cached by macos/set-lock-text.sh — shared with macos/defaults.sh."
        if [ -n "${NewSysName:-}" ]; then
            echo "NewSysName=$(printf '%q' "$NewSysName")"
        fi
        echo "RecoveryPhone=$(printf '%q' "$RecoveryPhone")"
        echo "RecoveryEmail=$(printf '%q' "$RecoveryEmail")"
    } > "$CACHE_FILE"
    chmod 600 "$CACHE_FILE"
    echo "  ✓ cached to $CACHE_FILE"
fi

LoginMsg=$(printf '%s\n%s\n%s\n%s' \
    "    F E D E R É A L     W A R N I N G" \
    "   ━━━━━━━━━━━━━━━━━" \
    "Certain Nuclear meltdown when wrong credentials are used." \
    "Call $RecoveryPhone, or mail at $RecoveryEmail")

sudo defaults write /Library/Preferences/com.apple.loginwindow LoginwindowText "$LoginMsg"
echo "  ✓ lock-screen recovery message applied"
