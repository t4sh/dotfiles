#!/usr/bin/env bash
# Restore app preferences from the repo into macOS.
#
# Single source of truth for both first-run (install.sh) and ongoing
# maintenance (make restore-apps, part of make all). Terminal.app is
# intentionally NOT handled here — it quits the parent shell on import,
# so it lives in `make terminal` as a manual target.
#
# Each block is a no-op if the repo file is missing; order-independent.
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"

echo "Restoring app preferences..."

# Bulk `defaults`-managed apps — driven by apps.tsv (domain ⇥ label ⇥ plist).
# Apps needing container copies / exclusions stay as explicit blocks below.
while IFS=$'\t' read -r domain label plist; do
    [ -z "${domain:-}" ] && continue
    case "$domain" in \#*) continue ;; esac
    if [ -f "$DOTFILES/$plist" ]; then
        defaults import "$domain" "$DOTFILES/$plist"
        echo "  ✓ $label"
    fi
done < "$DOTFILES/apps.tsv"

# Dato (cp plist into app's container)
DATO_DST="$HOME/Library/Group Containers/group.com.sindresorhus.Dato/Library/Preferences/group.com.sindresorhus.Dato.plist"
if [ -f "$DOTFILES/apps/dato/dato.plist" ] && [ -d "$(dirname "$DATO_DST")" ]; then
    cp "$DOTFILES/apps/dato/dato.plist" "$DATO_DST"
    echo "  ✓ Dato"
fi

# Sublime Text (cp into Packages/User/; Monokai license file is vault-only)
SUBLIME_USER="$HOME/Library/Application Support/Sublime Text/Packages/User"
MONOKAI_VAULT="$HOME/.secrets/apps/sublime-text/Theme - Monokai Pro.sublime-settings"
if [ -d "$DOTFILES/apps/sublime-text" ] && [ -n "$(ls -A "$DOTFILES/apps/sublime-text" 2>/dev/null)" ]; then
    mkdir -p "$SUBLIME_USER"
    for f in "$DOTFILES/apps/sublime-text/"*; do
        [[ -e "$f" ]] || continue
        base="${f##*/}"
        [[ "$base" == "Theme - Monokai Pro.sublime-settings" ]] && continue
        cp "$f" "$SUBLIME_USER/"
    done
    echo "  ✓ Sublime Text"
fi
if [ -f "$MONOKAI_VAULT" ]; then
    mkdir -p "$SUBLIME_USER"
    cp "$MONOKAI_VAULT" "$SUBLIME_USER/"
    echo "  ✓ Sublime Text (Monokai Pro license from vault)"
fi

# VS Code settings.json
VSCODE_USER="$HOME/Library/Application Support/Code/User"
if [ -f "$DOTFILES/apps/vscode/settings.json" ]; then
    mkdir -p "$VSCODE_USER"
    cp "$DOTFILES/apps/vscode/settings.json" "$VSCODE_USER/settings.json"
    echo "  ✓ VS Code"
fi

# Cursor settings.json (defaults domain is in apps.tsv; User/settings.json is copied)
CURSOR_USER="$HOME/Library/Application Support/Cursor/User"
if [ -f "$DOTFILES/apps/cursor/settings.json" ]; then
    mkdir -p "$CURSOR_USER"
    cp "$DOTFILES/apps/cursor/settings.json" "$CURSOR_USER/settings.json"
    echo "  ✓ Cursor"
fi

# Shottr — license prefs live in the vault (make restore-shottr after secrets restore).
# Canary Mail — sandbox realms + plist; vault via make restore-canary
# (see apps/canary-mail/README.md). Not part of restore-apps.

echo "Done. Terminal.app is handled separately: run 'make terminal' from a"
echo "non-Terminal shell (iTerm / Ghostty / VS Code integrated terminal)."
