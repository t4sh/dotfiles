# shared running-app gate for preference restore scripts
# shellcheck shell=bash
#
# Fail closed around running managed apps:
#   1. Detection error → refuse unless DOTFILES_RESTORE_FORCE=1
#   2. Warn per app, request graceful quit, refuse if any remain (FORCE override)
#   3. Record reopen responsibility before quit/wait; caller EXIT trap reopens
#   4. Never quit the resolved host editor; ambiguous Code markers defer both
#
# Usage (from a restore script):
#   # shellcheck source=scripts/lib/running-app-gate.sh
#   source "$DOTFILES/scripts/lib/running-app-gate.sh"
#   trap restore_reopen_apps EXIT   # must be before restore_running_app_gate
#   restore_running_app_gate "Rectangle:Rectangle" "Cursor:Cursor"
#
# Entry format: Label:AppleScriptName
#
# Environment:
#   DOTFILES_RESTORE_FORCE=1   proceed despite detection errors / still-running apps
#   DOTFILES_RESTORE_NO_QUIT=1 warn + refuse only; do not send quit Apple Events
#   DOTFILES_OPEN_BIN          override for reopen (tests)

# Populated by restore_running_app_gate. Call restore_reopen_apps from the
# restore script's EXIT cleanup so apps that were quit return to their prior
# running state. Host editors are tracked separately and their prefs are skipped.
RESTORE_APPS_TO_REOPEN=()
RESTORE_APPS_DEFERRED=()
RESTORE_OPEN_BIN="${DOTFILES_OPEN_BIN:-/usr/bin/open}"
# Cached host-editor result. State is exact, none, or ambiguous; the latter
# fails closed for both supported Code-family editors.
RESTORE_HOST_EDITOR_RESOLVED=""
RESTORE_HOST_EDITOR_STATE="unresolved"
RESTORE_HOST_EDITOR_CACHED=0

append_reopen_unique() {
  local value="$1" existing
  for existing in "${RESTORE_APPS_TO_REOPEN[@]}"; do
    [[ "$existing" == "$value" ]] && return 0
  done
  RESTORE_APPS_TO_REOPEN+=("$value")
}

append_deferred_unique() {
  local value="$1" existing
  for existing in "${RESTORE_APPS_DEFERRED[@]}"; do
    [[ "$existing" == "$value" ]] && return 0
  done
  RESTORE_APPS_DEFERRED+=("$value")
}

# Returns 0 when running, 1 when not running, and 2 when detection failed.
app_is_running() {
  local app_name="$1" result
  if ! result="$(osascript -e "application \"$app_name\" is running" 2>/dev/null)"; then
    return 2
  fi
  case "$result" in
    true) return 0 ;;
    false) return 1 ;;
    *) return 2 ;;
  esac
}

# Resolve host-editor state for this shell in the current process.
# Prefer Cursor-specific markers, then process identity of VSCODE_PID, then
# VS Code-only signals. Shared or unresolvable Code-family signals are
# ambiguous, so both editors are protected rather than neither.
restore_resolve_host_editor() {
  if [[ "$RESTORE_HOST_EDITOR_CACHED" -eq 1 ]]; then
    return 0
  fi
  RESTORE_HOST_EDITOR_CACHED=1
  RESTORE_HOST_EDITOR_RESOLVED=""
  RESTORE_HOST_EDITOR_STATE="none"

  if [[ -n "${CURSOR_TRACE_ID:-}${CURSOR_AGENT:-}${CURSOR_EXTENSION_HOST_ROLE:-}" ]]; then
    RESTORE_HOST_EDITOR_RESOLVED="Cursor"
    RESTORE_HOST_EDITOR_STATE="exact"
    return 0
  fi

  local askpass="${VSCODE_GIT_ASKPASS_MAIN:-${VSCODE_ASKPASS_MAIN:-}}"
  case "$askpass" in
    *Cursor.app*|*"/Cursor/"*)
      RESTORE_HOST_EDITOR_RESOLVED="Cursor"
      RESTORE_HOST_EDITOR_STATE="exact"
      return 0
      ;;
    *"Visual Studio Code.app"*|*"/Code.app/"*)
      RESTORE_HOST_EDITOR_RESOLVED="Visual Studio Code"
      RESTORE_HOST_EDITOR_STATE="exact"
      return 0
      ;;
  esac

  if [[ -n "${VSCODE_PID:-}" ]] && [[ "${VSCODE_PID}" =~ ^[0-9]+$ ]]; then
    local args=""
    args="$(ps -p "$VSCODE_PID" -o args= 2>/dev/null || true)"
    case "$args" in
      *Cursor.app*|*"/Cursor/"*)
        RESTORE_HOST_EDITOR_RESOLVED="Cursor"
        RESTORE_HOST_EDITOR_STATE="exact"
        return 0
        ;;
      *"Visual Studio Code.app"*|*"/Code.app/"*)
        RESTORE_HOST_EDITOR_RESOLVED="Visual Studio Code"
        RESTORE_HOST_EDITOR_STATE="exact"
        return 0
        ;;
    esac
  fi

  if [[ "${TERM_PROGRAM:-}" == "vscode" || -n "${VSCODE_PID:-}${VSCODE_INJECTION:-}${askpass:-}" ]]; then
    RESTORE_HOST_EDITOR_STATE="ambiguous"
  fi
  return 0
}

restore_host_editor_name() {
  restore_resolve_host_editor
  printf '%s' "$RESTORE_HOST_EDITOR_RESOLVED"
}

# True for the exact host, or for either Code-family editor when host identity
# is ambiguous and quitting either could terminate this restore.
is_restore_host_app() {
  local app_name="$1"
  restore_resolve_host_editor
  if [[ "$RESTORE_HOST_EDITOR_STATE" == "exact" ]]; then
    [[ "$app_name" == "$RESTORE_HOST_EDITOR_RESOLVED" ]]
    return
  fi
  if [[ "$RESTORE_HOST_EDITOR_STATE" == "ambiguous" ]]; then
    [[ "$app_name" == "Cursor" || "$app_name" == "Visual Studio Code" ]]
    return
  fi
  return 1
}

# Quit via AppleScript. Best-effort; caller re-checks.
app_request_quit() {
  local app_name="$1"
  osascript -e "tell application \"$app_name\" to quit" >/dev/null 2>&1 || true
}

restore_app_is_deferred() {
  local app_name="$1" deferred
  for deferred in "${RESTORE_APPS_DEFERRED[@]}"; do
    [[ "$deferred" == "$app_name" ]] && return 0
  done
  return 1
}

restore_reopen_apps() {
  local app_name
  for app_name in "${RESTORE_APPS_TO_REOPEN[@]}"; do
    if "$RESTORE_OPEN_BIN" -g -a "$app_name" >/dev/null 2>&1; then
      printf '  ✓ reopened %s\n' "$app_name"
    else
      printf '\033[33m  ⚠ could not reopen %s; launch it manually\033[0m\n' "$app_name" >&2
    fi
  done
  RESTORE_APPS_TO_REOPEN=()
}

# Args: one or more "Label:AppleScriptName" entries.
restore_running_app_gate() {
  local entry label app_name detection_rc=0 detection_failed=0
  local -a running_labels=() running_apps=()
  local -a still_labels=() still_apps=()
  local force="${DOTFILES_RESTORE_FORCE:-0}"
  local no_quit="${DOTFILES_RESTORE_NO_QUIT:-0}"

  # Resolve once in the caller shell so cache and ambiguity state persist.
  restore_resolve_host_editor

  for entry in "$@"; do
    label="${entry%%:*}"
    app_name="${entry#*:}"
    [[ -n "$label" && -n "$app_name" && "$label" != "$entry" ]] || continue
    app_is_running "$app_name" || detection_rc=$?
    case "$detection_rc" in
      0)
        if is_restore_host_app "$app_name"; then
          append_deferred_unique "$app_name"
          if [[ "$RESTORE_HOST_EDITOR_STATE" == "ambiguous" ]]; then
            printf '  ⚠ Code-family host identity is ambiguous; %s preferences will be skipped\n' "$label"
          else
            printf '  ⚠ %s is the restore host; its preferences will be skipped\n' "$label"
          fi
        else
          running_labels+=("$label")
          running_apps+=("$app_name")
        fi
        ;;
      1) ;;
      *)
        printf '\033[31merror:\033[0m could not determine whether %s is running\n' "$label" >&2
        detection_failed=1
        ;;
    esac
    detection_rc=0
  done

  if (( detection_failed )); then
    if [[ "$force" == "1" ]]; then
      echo "  → DOTFILES_RESTORE_FORCE=1 set; continuing despite app-state detection errors"
    else
      echo "  rerun after AppleScript is available, or explicitly set DOTFILES_RESTORE_FORCE=1" >&2
      return 1
    fi
  fi

  if ((${#running_labels[@]} == 0)); then
    return 0
  fi

  printf '\033[1m⚠ %d managed app(s) still running — prefs can overwrite restored state on quit:\033[0m\n' "${#running_labels[@]}"
  local i
  for i in "${!running_labels[@]}"; do
    printf '  ⚠ %s (application "%s")\n' "${running_labels[$i]}" "${running_apps[$i]}"
  done

  if [[ "$no_quit" != "1" ]]; then
    echo "  → requesting quit…"
    # Record reopen responsibility before quit/wait — sleep can fail/interrupt
    # under set -e and must not strand apps that already quit.
    for i in "${!running_apps[@]}"; do
      append_reopen_unique "${running_apps[$i]}"
      app_request_quit "${running_apps[$i]}"
    done
    sleep 2 || true
  else
    echo "  → DOTFILES_RESTORE_NO_QUIT=1 set; not sending quit"
  fi

  still_labels=()
  still_apps=()
  for i in "${!running_apps[@]}"; do
    detection_rc=0
    app_is_running "${running_apps[$i]}" || detection_rc=$?
    case "$detection_rc" in
      0)
        still_labels+=("${running_labels[$i]}")
        still_apps+=("${running_apps[$i]}")
        ;;
      1) ;;
      *)
        printf '\033[31merror:\033[0m could not confirm whether %s quit\n' "${running_labels[$i]}" >&2
        still_labels+=("${running_labels[$i]}")
        still_apps+=("${running_apps[$i]}")
        ;;
    esac
  done

  if ((${#still_labels[@]} == 0)); then
    echo "  ✓ all previously running managed apps quit; continuing restore"
    return 0
  fi

  if [[ "$no_quit" == "1" ]]; then
    printf '\033[1m⚠ still running (quit not requested):\033[0m\n'
  else
    printf '\033[1m⚠ still running after quit attempt:\033[0m\n'
  fi
  for i in "${!still_labels[@]}"; do
    printf '  ✗ %s\n' "${still_labels[$i]}"
  done

  if [[ "$force" == "1" ]]; then
    echo "  → DOTFILES_RESTORE_FORCE=1 set; continuing (restored prefs may bounce when those apps exit)"
    return 0
  fi

  printf '\033[31merror:\033[0m refusing restore while managed apps are running\n' >&2
  echo "  quit the apps above, then re-run" >&2
  echo "  or: DOTFILES_RESTORE_FORCE=1 <restore-command>  # proceed anyway" >&2
  echo "  or: DOTFILES_RESTORE_NO_QUIT=1 …             # warn+refuse without sending quit" >&2
  restore_reopen_apps
  return 1
}
