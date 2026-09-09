#!/usr/bin/env bash
# Windows uses native entry points; reject before any Unix-path mutation.
case "${OS:-}:$(uname -s)" in
  Windows_NT:*|*:MINGW*|*:MSYS*) echo 'This is a macOS workflow. On Windows run bin/dot.cmd help.' >&2; exit 2 ;;
esac
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

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
bash "$DOTFILES/scripts/validate-manifests.sh" apps

materialize_editor_file() {
    local source="$1" destination="$2" prefix tmp
    mkdir -p "$(dirname "$destination")"
    if ! grep -q '__HOMEBREW_PREFIX__' "$source"; then
        cp "$source" "$destination"
        return
    fi
    command -v brew >/dev/null 2>&1 || {
        echo "Homebrew is required to materialize editor paths in $source" >&2
        return 1
    }
    prefix="$(brew --prefix)"
    tmp="$(mktemp "$(dirname "$destination")/.dotfiles-editor.XXXXXX")"
    if ! HOMEBREW_PREFIX="$prefix" perl -pe \
        's/__HOMEBREW_PREFIX__/$ENV{HOMEBREW_PREFIX}/g' "$source" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    if ! chmod 600 "$tmp" || ! mv "$tmp" "$destination"; then
        rm -f "$tmp"
        return 1
    fi
}

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
[[ -f "$DOTFILES/apps/tower/ai-prompts.plist" ]] && append_restore_gate_entry "Tower" "Tower"
if [[ -f "$DOTFILES/apps/dato/dato.plist" || -f "$DOTFILES/apps/dato/display.plist" ]]; then
    append_restore_gate_entry "Dato" "Dato"
fi
[[ -d "$DOTFILES/apps/sublime-text" ]] && append_restore_gate_entry "Sublime Text" "Sublime Text"
[[ -f "$DOTFILES/apps/mountain-duck/sync.plist" ]] && append_restore_gate_entry "Mountain Duck" "Mountain Duck"
[[ -f "$DOTFILES/apps/vscode/settings.json" ]] && append_restore_gate_entry "VS Code" "Visual Studio Code"
[[ -f "$DOTFILES/apps/cursor/settings.json" ]] && append_restore_gate_entry "Cursor" "Cursor"
if [[ -f "$DOTFILES/apps/zed/settings.json" || -f "$DOTFILES/apps/zed/keymap.json" ]]; then
    append_restore_gate_entry "Zed" "Zed"
fi

restore_running_app_gate "${RESTORE_GATE_ENTRIES[@]}"

# Whole-domain macOS system snapshots (Keyboard Shortcuts and Input Sources)
# are imported via `defaults import`, but cfprefsd caches these domains. Track
# exactly which snapshots were imported so the cache refresh and read-back
# summary cannot claim that an absent domain was restored.
RESTORE_DEFERRED_DOMAINS=()
RESTORE_DEFERRED_LABELS=()
RESTORE_DEFERRED_PLISTS=()

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
        # Keep in sync with the two macos/ rows in apps.tsv (no owning app; cfprefsd caches them).
        case "$domain" in
            com.apple.symbolichotkeys|com.apple.HIToolbox)
                RESTORE_DEFERRED_DOMAINS+=("$domain")
                RESTORE_DEFERRED_LABELS+=("$label")
                RESTORE_DEFERRED_PLISTS+=("$DOTFILES/$plist")
                ;;
        esac
    fi
done < "$DOTFILES/apps.tsv"

# Restore only the managed Mountain Duck key, preserving other preferences.
if [[ -f "$DOTFILES/apps/mountain-duck/sync.plist" ]]; then
    if restore_app_is_deferred "Mountain Duck"; then
        echo "  - Mountain Duck skipped because it hosts this restore"
    else
        mountain_duck_pattern="$(plutil -extract temporaryFilenamePattern raw -o - "$DOTFILES/apps/mountain-duck/sync.plist")"
        defaults write io.mountainduck fs.filenames.temporary.regexp -string "$mountain_duck_pattern"
        echo "  ✓ Mountain Duck sync exclusions"
    fi
fi

# Tower AI prompts live outside the defaults domain; the list includes its default.
if [[ -f "$DOTFILES/apps/tower/ai-prompts.plist" ]]; then
    if restore_app_is_deferred "Tower"; then
        echo "  - Tower AI prompts skipped because it hosts this restore"
    else
        plutil -lint "$DOTFILES/apps/tower/ai-prompts.plist" >/dev/null
        mkdir -p "$HOME/Library/Application Support/com.fournova.Tower3"
        cp "$DOTFILES/apps/tower/ai-prompts.plist" \
            "$HOME/Library/Application Support/com.fournova.Tower3/ai-prompts.plist"
        echo "  ✓ Tower AI commit prompts"
    fi
fi

# Dato (cp plist into app's container)
DATO_DST="$HOME/Library/Group Containers/group.com.sindresorhus.Dato/Library/Preferences/group.com.sindresorhus.Dato.plist"
if [ -f "$DOTFILES/apps/dato/dato.plist" ]; then
    if restore_app_is_deferred "Dato"; then
        echo "  - Dato skipped because it hosts this restore"
    elif [ -d "$(dirname "$DATO_DST")" ]; then
        cp "$DOTFILES/apps/dato/dato.plist" "$DATO_DST"
        echo "  ⚠ Dato shared time-zone snapshot copied — this alone does not restore the active clock list; display format is handled separately"
    else
        echo "  ⚠ Dato not restored — launch it once to create its group container, then re-run make restore-apps"
    fi
fi

# Restore only the captured display key; preserve other primary preferences.
DATO_PRIMARY="$HOME/Library/Containers/com.sindresorhus.Dato/Data/Library/Preferences/com.sindresorhus.Dato.plist"
if [[ -f "$DOTFILES/apps/dato/display.plist" ]]; then
    if restore_app_is_deferred "Dato"; then
        echo "  - Dato display skipped because it hosts this restore"
    elif [[ -d "$(dirname "$DATO_PRIMARY")" ]]; then
        DATO_FORMAT="$(plutil -extract dateTimeFormat raw -o - "$DOTFILES/apps/dato/display.plist")"
        defaults write "${DATO_PRIMARY%.plist}" dateTimeFormat -string "$DATO_FORMAT"
        echo "  ✓ Dato custom date/time format (other primary preferences are not restored)"
    else
        echo "  ⚠ Dato display not restored — launch Dato once, then re-run make restore-apps"
    fi
fi

# Sublime Text (cp into Packages/User/; Monokai license file is vault-only)
SUBLIME_USER="$HOME/Library/Application Support/Sublime Text/Packages/User"
MONOKAI_VAULT="$HOME/.secrets/apps/sublime-text/Theme - Monokai Pro.sublime-settings"
if [ -d "$DOTFILES/apps/sublime-text" ] && [ -n "$(ls -A "$DOTFILES/apps/sublime-text" 2>/dev/null)" ]; then
    if restore_app_is_deferred "Sublime Text"; then
        echo "  - Sublime Text skipped because it hosts this restore"
    else
        bash "$DOTFILES/scripts/sync-sublime-settings.sh" restore
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
        materialize_editor_file "$DOTFILES/apps/vscode/settings.json" "$VSCODE_USER/settings.json"
        echo "  ✓ VS Code"
    fi
fi

# Cursor settings.json (defaults domain is in apps.tsv; User/settings.json is copied)
CURSOR_USER="$HOME/Library/Application Support/Cursor/User"
if [ -f "$DOTFILES/apps/cursor/settings.json" ]; then
    if restore_app_is_deferred "Cursor"; then
        echo "  - Cursor settings skipped because it hosts this restore"
    else
        materialize_editor_file "$DOTFILES/apps/cursor/settings.json" "$CURSOR_USER/settings.json"
        echo "  ✓ Cursor"
    fi
fi

# Zed settings and keymap (account/provider/agent auth remains app-managed)
if [ -f "$DOTFILES/apps/zed/settings.json" ] || [ -f "$DOTFILES/apps/zed/keymap.json" ]; then
    if restore_app_is_deferred "Zed"; then
        echo "  - Zed settings skipped because it hosts this restore"
    else
        for file in settings.json keymap.json; do
            [ -f "$DOTFILES/apps/zed/$file" ] || continue
            materialize_editor_file "$DOTFILES/apps/zed/$file" "$HOME/.config/zed/$file"
        done
        echo "  ✓ Zed"
    fi
fi

# Shottr — license prefs live in the vault (make restore-shottr after secrets restore).
# Canary Mail — sandbox realms + plist; vault via make restore-canary
# (see apps/canary-mail/README.md). Not part of restore-apps.

verify_deferred_imports() {
    local index domain label source live_plist failures=0
    if ! command -v python3 >/dev/null 2>&1 || \
       [[ ! -f "$DOTFILES/scripts/lib/plist_drift.py" ]]; then
        echo "  ⚠ semantic read-back unavailable; log out and back in, then run make apps-drift." >&2
        return 1
    fi
    for ((index = 0; index < ${#RESTORE_DEFERRED_DOMAINS[@]}; index++)); do
        domain="${RESTORE_DEFERRED_DOMAINS[index]}"
        label="${RESTORE_DEFERRED_LABELS[index]}"
        source="${RESTORE_DEFERRED_PLISTS[index]}"
        live_plist="$(mktemp "${TMPDIR:-/tmp}/dotfiles-deferred-pref.XXXXXX")"
        # The shared comparator deliberately ignores current/selected input
        # source runtime state; this verifies the portable managed values.
        if defaults export "$domain" "$live_plist" >/dev/null 2>&1 && \
           python3 "$DOTFILES/scripts/lib/plist_drift.py" "$live_plist" "$source" >/dev/null; then
            echo "  ✓ $label managed preference read-back matches"
        else
            echo "  ⚠ $label managed preference read-back did not match; log out and back in, then run make apps-drift." >&2
            failures=$((failures + 1))
        fi
        rm -f "$live_plist"
    done
    (( failures == 0 ))
}

if (( ${#RESTORE_DEFERRED_DOMAINS[@]} > 0 )); then
    deferred_summary="${RESTORE_DEFERRED_LABELS[0]}"
    cfprefsd_running=-1
    for ((index = 1; index < ${#RESTORE_DEFERRED_LABELS[@]}; index++)); do
        deferred_summary+=", ${RESTORE_DEFERRED_LABELS[index]}"
    done
    echo
    if command -v killall >/dev/null 2>&1; then
        if command -v pgrep >/dev/null 2>&1; then
            pgrep_status=0
            pgrep -u "$(id -u)" -x cfprefsd >/dev/null 2>&1 || pgrep_status=$?
            case "$pgrep_status" in
                0) cfprefsd_running=1 ;;
                1) cfprefsd_running=0 ;;
            esac
        fi
        if (( cfprefsd_running == 0 )); then
            echo "  → current user's cfprefsd was not running; no restart needed for: $deferred_summary"
            verify_deferred_imports || true
        elif killall -u "$(id -un)" cfprefsd 2>/dev/null; then
            echo "  → restarted the current user's cfprefsd for: $deferred_summary"
            verify_deferred_imports || true
        else
            echo "  ⚠ could not restart cfprefsd for: $deferred_summary" >&2
            echo "    log out and back in to apply those preferences." >&2
        fi
    else
        echo "  → log out and back in to apply: $deferred_summary"
    fi
fi

echo "Done. Terminal.app is handled separately: run 'make terminal' from a"
echo "non-Terminal shell (iTerm / Ghostty / VS Code / Cursor / Zed integrated terminal)."
