#!/usr/bin/env bash
# Restore app preferences from the repo into macOS.
#
# Single source of truth for both first-run (install.sh) and ongoing
# maintenance (make restore-apps, part of make all). Terminal.app is
# intentionally NOT handled here — it quits the parent shell on import,
# so it lives in `make terminal` as a manual target.
#
# Running-app policy: warn per managed app, request quit, then refuse unless
# DOTFILES_RESTORE_FORCE=1 (see scripts/lib/running-app-gate.sh).
#
# Each restore block is a no-op if the repo file is missing; order-independent.
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"

# shellcheck source=scripts/lib/running-app-gate.sh
source "$DOTFILES/scripts/lib/running-app-gate.sh"
trap restore_reopen_apps EXIT

echo "Restoring app preferences..."

# Derive regular applications from apps.tsv so new restore rows cannot bypass
# the safety gate. Irregular copies remain explicit below.
RESTORE_GATE_ENTRIES=()
append_restore_gate_entry() {
    local label="$1" app_name="$2" existing
    for existing in "${RESTORE_GATE_ENTRIES[@]}"; do
        [[ "${existing#*:}" == "$app_name" ]] && return 0
    done
    RESTORE_GATE_ENTRIES+=("$label:$app_name")
}

while IFS=$'\t' read -r domain label plist app_name; do
    [ -z "${domain:-}" ] && continue
    case "$domain" in \#*) continue ;; esac
    app_name="${app_name:-$label}"
    [[ "$app_name" == "-" || ! -f "$DOTFILES/$plist" ]] && continue
    append_restore_gate_entry "$label" "$app_name"
done < "$DOTFILES/apps.tsv"
[[ -f "$DOTFILES/apps/dato/dato.plist" ]] && append_restore_gate_entry "Dato" "Dato"
[[ -d "$DOTFILES/apps/sublime-text" ]] && append_restore_gate_entry "Sublime Text" "Sublime Text"
[[ -f "$DOTFILES/apps/vscode/settings.json" ]] && append_restore_gate_entry "VS Code" "Visual Studio Code"
[[ -f "$DOTFILES/apps/cursor/settings.json" ]] && append_restore_gate_entry "Cursor" "Cursor"

restore_running_app_gate "${RESTORE_GATE_ENTRIES[@]}"

# Bulk `defaults`-managed apps — driven by apps.tsv (domain ⇥ label ⇥ plist).
# Apps needing container copies / exclusions stay as explicit blocks below.
while IFS=$'\t' read -r domain label plist app_name; do
    [ -z "${domain:-}" ] && continue
    case "$domain" in \#*) continue ;; esac
    app_name="${app_name:-$label}"
    if [[ "$app_name" != "-" ]] && restore_app_is_deferred "$app_name"; then
        echo "  - $label skipped because it hosts this restore"
        continue
    fi
    if [ -f "$DOTFILES/$plist" ]; then
        defaults import "$domain" "$DOTFILES/$plist"
        echo "  ✓ $label"
    fi
done < "$DOTFILES/apps.tsv"

# Dato (cp plist into app's container)
DATO_DST="$HOME/Library/Group Containers/group.com.sindresorhus.Dato/Library/Preferences/group.com.sindresorhus.Dato.plist"
if [ -f "$DOTFILES/apps/dato/dato.plist" ]; then
    if restore_app_is_deferred "Dato"; then
        echo "  - Dato skipped because it hosts this restore"
    elif [ -d "$(dirname "$DATO_DST")" ]; then
        cp "$DOTFILES/apps/dato/dato.plist" "$DATO_DST"
        echo "  ✓ Dato"
    else
        echo "  ⚠ Dato not restored — launch it once to create its group container, then re-run make restore-apps"
    fi
fi

# Sublime Text (cp into Packages/User/; Monokai license file is vault-only)
SUBLIME_USER="$HOME/Library/Application Support/Sublime Text/Packages/User"
MONOKAI_VAULT="$HOME/.secrets/apps/sublime-text/Theme - Monokai Pro.sublime-settings"
if [ -d "$DOTFILES/apps/sublime-text" ] && [ -n "$(ls -A "$DOTFILES/apps/sublime-text" 2>/dev/null)" ]; then
    if restore_app_is_deferred "Sublime Text"; then
        echo "  - Sublime Text skipped because it hosts this restore"
    else
        mkdir -p "$SUBLIME_USER"
        for f in "$DOTFILES/apps/sublime-text/"*; do
            [[ -e "$f" ]] || continue
            base="${f##*/}"
            [[ "$base" == "Theme - Monokai Pro.sublime-settings" ]] && continue
            cp "$f" "$SUBLIME_USER/"
        done
        echo "  ✓ Sublime Text"
    fi
fi
if [ -f "$MONOKAI_VAULT" ] && ! restore_app_is_deferred "Sublime Text"; then
    mkdir -p "$SUBLIME_USER"
    cp "$MONOKAI_VAULT" "$SUBLIME_USER/"
    echo "  ✓ Sublime Text (Monokai Pro license from vault)"
fi

# VS Code settings.json
VSCODE_USER="$HOME/Library/Application Support/Code/User"
if [ -f "$DOTFILES/apps/vscode/settings.json" ]; then
    if restore_app_is_deferred "Visual Studio Code"; then
        echo "  - VS Code skipped because it hosts this restore"
    else
        mkdir -p "$VSCODE_USER"
        cp "$DOTFILES/apps/vscode/settings.json" "$VSCODE_USER/settings.json"
        echo "  ✓ VS Code"
    fi
fi

# Cursor settings.json (defaults domain is in apps.tsv; User/settings.json is copied)
CURSOR_USER="$HOME/Library/Application Support/Cursor/User"
if [ -f "$DOTFILES/apps/cursor/settings.json" ]; then
    if restore_app_is_deferred "Cursor"; then
        echo "  - Cursor settings skipped because it hosts this restore"
    else
        mkdir -p "$CURSOR_USER"
        cp "$DOTFILES/apps/cursor/settings.json" "$CURSOR_USER/settings.json"
        echo "  ✓ Cursor"
    fi
fi

# Shottr — license prefs live in the vault (make restore-shottr after secrets restore).
# Canary Mail — sandbox realms + plist; vault via make restore-canary
# (see apps/canary-mail/README.md). Not part of restore-apps.

echo "Done. Terminal.app is handled separately: run 'make terminal' from a"
echo "non-Terminal shell (iTerm / Ghostty / VS Code integrated terminal)."
