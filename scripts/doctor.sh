#!/usr/bin/env bash
# Windows uses native entry points; reject before any Unix-path mutation.
case "${OS:-}:$(uname -s)" in
  Windows_NT:*|*:MINGW*|*:MSYS*) echo 'This is a macOS workflow. On Windows run bin/dot.cmd help.' >&2; exit 2 ;;
esac
# Read-only preflight checks for a fresh or re-applied Mac bootstrap.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
WARNINGS=0
FAILURES=0
STRICT=0
CHECK_TIMEOUT="${DOTFILES_DOCTOR_TIMEOUT:-30}"
AUDIT_TIMEOUT="${DOTFILES_DOCTOR_AUDIT_TIMEOUT:-120}"

while (($# > 0)); do
  case "$1" in
    --strict) STRICT=1 ;;
    -h|--help)
      echo "usage: doctor.sh [--strict]"
      echo "  --strict  return nonzero when any warning remains"
      exit 0
      ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

[[ "$CHECK_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || { echo "DOTFILES_DOCTOR_TIMEOUT must be a positive integer" >&2; exit 2; }
[[ "$AUDIT_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || { echo "DOTFILES_DOCTOR_AUDIT_TIMEOUT must be a positive integer" >&2; exit 2; }

ok() { printf '  ✓ %s\n' "$1"; }
note() { printf '  - %s\n' "$1"; }
warn() { printf '  ⚠ %s\n' "$1"; WARNINGS=$((WARNINGS + 1)); }
fail() { printf '  ✗ %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

have() { command -v "$1" >/dev/null 2>&1; }

# Classify DockerHelper records in `sfltool dumpbtm` output.
# Prints one of: enabled | disabled | absent
# A registered helper without an explicit [disabled] disposition is treated as
# enabled — dumpbtm does not always print Disposition.
docker_helper_btm_state() {
  awk '
    function flush() {
      if (!helper) return
      if (disposition ~ /\[disabled/) {
        if (!any_enabled) any_disabled = 1
      } else {
        any_enabled = 1
      }
    }
    /^[[:space:]]*#[0-9]+:/ {
      flush()
      helper = 0
      disposition = ""
      next
    }
    {
      low = tolower($0)
    }
    low ~ /^[[:space:]]*name:[[:space:]]*dockerhelper[[:space:]]*$/ { helper = 1 }
    low ~ /^[[:space:]]*bundle identifier:[[:space:]]*com\.docker\.helper[[:space:]]*$/ { helper = 1 }
    low ~ /^[[:space:]]*identifier:[[:space:]]*/ {
      id = low
      sub(/^[[:space:]]*identifier:[[:space:]]*/, "", id)
      sub(/[[:space:]]+$/, "", id)
      sub(/^[[:digit:]]+\./, "", id)
      if (id == "com.docker.helper") helper = 1
    }
    low ~ /^[[:space:]]*disposition:/ { disposition = low }
    END {
      flush()
      if (any_enabled) print "enabled"
      else if (any_disabled) print "disabled"
      else print "absent"
    }
  '
}

run_with_timeout() {
  local seconds="$1" pid watchdog status
  shift
  "$@" &
  pid=$!
  (
    sleep "$seconds"
    pkill -TERM -P "$pid" 2>/dev/null || true
    kill -TERM "$pid" 2>/dev/null || exit 0
    sleep 2
    pkill -KILL -P "$pid" 2>/dev/null || true
    kill -KILL "$pid" 2>/dev/null || true
  ) &
  watchdog=$!
  set +e
  wait "$pid"
  status=$?
  set -e
  kill "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  if (( status == 137 || status == 143 )); then
    return 124
  fi
  return "$status"
}

check_docker_helper() {
  local docker_app dump status state
  docker_app="${DOTFILES_DOCKER_APP:-/Applications/Docker.app}"
  if [ ! -d "$docker_app" ]; then
    note "Docker.app not installed; DockerHelper login-item check skipped"
    return 0
  fi
  if ! have sfltool; then
    note "sfltool missing; DockerHelper login-item check skipped"
    return 0
  fi
  dump=""
  status=0
  dump="$(run_with_timeout "$CHECK_TIMEOUT" sfltool dumpbtm 2>/dev/null)" || status=$?
  if (( status == 124 )); then
    warn "DockerHelper login-item check timed out after ${CHECK_TIMEOUT}s"
    return 0
  fi
  if (( status != 0 )); then
    warn "DockerHelper login-item check failed (exit ${status}); inspect Docker in System Settings → General → Login Items & Extensions"
    return 0
  fi
  if [ -z "${dump//[$'\t\n\r ']/}" ]; then
    warn "DockerHelper login-item check returned no data; inspect Docker in System Settings → General → Login Items & Extensions"
    return 0
  fi
  state="$(printf '%s\n' "$dump" | docker_helper_btm_state)"
  case "$state" in
    enabled)
      warn "DockerHelper is an enabled macOS login item; the menu-bar tray can open the Docker dashboard even when AutoStart is off. Disable Docker / DockerHelper in System Settings → General → Login Items & Extensions → Allow in the Background. Doctor will not change this setting."
      ;;
    disabled)
      ok "DockerHelper login item is disabled"
      ;;
    *)
      ok "DockerHelper is not registered as a login item"
      ;;
  esac
}

check_command() {
  local command_name="$1" label="$2"
  if have "$command_name"; then
    ok "$label"
  else
    warn "$label missing"
  fi
}

check_executable() {
  local path="$1" label="$2"
  if [ -x "$path" ]; then
    ok "$label"
  else
    warn "$label missing or not executable: $path"
  fi
}

echo "Dotfiles doctor"
echo "================"

if xcode-select -p >/dev/null 2>&1; then
  ok "Xcode Command Line Tools installed"
else
  fail "Xcode Command Line Tools missing"
fi

if have brew; then
  ok "Homebrew installed"
  # audit-brewfile performs one Homebrew inventory dump and compares both
  # directions: declared-but-missing and installed-but-undeclared. Running a
  # separate `brew bundle check` first doubled Doctor's slowest scan without
  # adding a distinct completion signal; `make brew-check` remains available
  # for an explicit installed-only diagnosis.
  echo "  … comparing installed and declared Brewfile state"
  if run_with_timeout "$AUDIT_TIMEOUT" bash "$DOTFILES/scripts/audit-brewfile.sh" --check >/dev/null 2>&1; then
    ok "Brewfile installed and declared state match"
  else
    status=$?
    if (( status == 124 )); then
      warn "Brewfile state audit timed out after ${AUDIT_TIMEOUT}s"
    else
      warn "Brewfile install/declaration drift detected; run: make brewfile-audit"
    fi
  fi
else
  fail "Homebrew missing"
fi

check_command duti "duti"
if have duti && [ -f "$DOTFILES/config/duti" ]; then
  expected_duti_digest="$(shasum -a 256 "$DOTFILES/config/duti" | awk '{print $1}')"
  expected_duti_receipt="v2:$expected_duti_digest"
  duti_receipt="$HOME/.dotfiles-local/default-apps.sha256"
  if [ -f "$duti_receipt" ] && [ "$(tr -d '[:space:]' < "$duti_receipt")" = "$expected_duti_receipt" ]; then
    ok "complete default-app policy applied (receipt matches config/duti)"
    note "live handler drift check: make default-apps-check"
  else
    warn "complete default-app policy not applied for this config; run: make default-apps"
  fi
fi
check_command gitleaks "gitleaks"

touch_id_hardware_status=0
bash "$DOTFILES/scripts/touch-id-sudo.sh" --hardware-check >/dev/null 2>&1 \
  || touch_id_hardware_status=$?
case "$touch_id_hardware_status" in
  0)
    if bash "$DOTFILES/scripts/touch-id-sudo.sh" --check >/dev/null 2>&1; then
      ok "Touch ID sudo enabled"
    else
      warn "Touch ID sudo not enabled; run: make touch-id-sudo"
    fi
    ;;
  1) note "Touch ID hardware not detected; password-only sudo policy accepted" ;;
  *) warn "Touch ID hardware detection failed; run: make touch-id-sudo-check" ;;
esac

if bash "$DOTFILES/scripts/check-services.sh" >/dev/null 2>&1; then
  ok "managed Automator workflows match installed copies"
else
  warn "managed Automator workflows missing or drifted; run: make services-check"
fi

check_docker_helper

if [ -f "$DOTFILES/.node-version" ]; then
  ok ".node-version present ($(tr -d '[:space:]' < "$DOTFILES/.node-version"))"
else
  warn ".node-version missing"
fi
check_executable "$HOME/.local/bin/node-stable" "node-stable shim"
check_executable "$HOME/.local/bin/npx-stable" "npx-stable shim"

if have python3 && [ -f "$DOTFILES/agents/.skill-lock.json" ] && [ -f "$DOTFILES/Skillsfile" ]; then
  if python3 "$DOTFILES/scripts/gen-skillsfile.py" --check >/dev/null 2>&1; then
    ok "Skillsfile in sync with agents/.skill-lock.json"
  else
    warn "Skillsfile out of sync; run: make skills-manifest"
  fi
else
  warn "Skillsfile sync check skipped (python3, lockfile, or Skillsfile missing)"
fi

if [ -d "/Applications/Hammerspoon.app" ] || have hs; then
  ok "Hammerspoon installed"

  if [ -L "$HOME/.hammerspoon" ] && [ "$(readlink "$HOME/.hammerspoon")" = "$DOTFILES/hammerspoon" ]; then
    ok "Hammerspoon config linked"
  else
    warn "Hammerspoon config is not linked to $DOTFILES/hammerspoon; run: make link"
  fi

  if pgrep -x Hammerspoon >/dev/null 2>&1; then
    ok "Hammerspoon running"
    if have hs; then
      accessibility_state="$(hs -c 'return hs.accessibilityState()' 2>/dev/null || true)"
      if [[ "$accessibility_state" == *true* ]]; then
        ok "Hammerspoon Accessibility permission granted"
      else
        warn "Hammerspoon Accessibility permission missing; enable it in System Settings > Privacy & Security > Accessibility"
      fi

      auto_launch_state="$(hs -c 'return hs.autoLaunch()' 2>/dev/null || true)"
      if [[ "$auto_launch_state" == *true* ]]; then
        ok "Hammerspoon Launch at Login enabled"
      else
        warn "Hammerspoon Launch at Login disabled; enable it in Hammerspoon preferences"
      fi
    else
      warn "Hammerspoon CLI missing; reload its config and rerun doctor"
    fi
  else
    warn "Hammerspoon not running; run: open -a Hammerspoon, then enable Launch at Login"
  fi
else
  warn "Hammerspoon missing"
fi
check_command typos "typos"

if have gh; then
  if run_with_timeout "$CHECK_TIMEOUT" env GH_HOST=github.com gh auth status --hostname github.com >/dev/null 2>&1; then
    ok "GitHub CLI authenticated"
  else
    warn "GitHub CLI installed but not authenticated"
  fi
else
  warn "GitHub CLI missing"
fi

if have mas; then
  echo "  … checking Mac App Store state"
  if run_with_timeout "$CHECK_TIMEOUT" mas config >/dev/null 2>&1 && \
     run_with_timeout "$CHECK_TIMEOUT" mas list >/dev/null 2>&1; then
    ok "Mac App Store CLI operational"
  else
    status=$?
    if (( status == 124 )); then
      warn "Mac App Store check timed out after ${CHECK_TIMEOUT}s"
    else
      warn "mas cannot query App Store state; open the App Store and verify sign-in"
    fi
  fi
else
  warn "mas missing"
fi

if [ -d "$HOME/.secrets" ]; then
  ok "$HOME/.secrets exists"
  # Warn-level readiness checks — presence only; never print secret contents.
  if [ -f "$HOME/.secrets/ssh/github_ed25519" ]; then
    ok "GitHub SSH private key present"
  else
    warn "GitHub SSH private key missing (~/.secrets/ssh/github_ed25519); restore/import secrets, then run: make post-vault"
  fi
  if [ -f "$HOME/.secrets/config/gh/hosts.yml" ]; then
    ok "GitHub CLI hosts.yml present"
  else
    warn "GitHub CLI hosts.yml missing (~/.secrets/config/gh/hosts.yml); restore/import secrets, then run: make post-vault"
  fi
else
  warn "$HOME/.secrets missing; restore vault before secret-backed symlinks work"
fi

post_vault_pending="$HOME/.dotfiles-local/post-vault.pending"
if [ -s "$post_vault_pending" ]; then
  pending_labels="$(awk 'BEGIN { sep = "" } { printf "%s%s", sep, $0; sep = ", " } END { print "" }' "$post_vault_pending" 2>/dev/null || true)"
  warn "post-vault restores still pending (${pending_labels:-unknown}); run: make post-vault"
fi

if [ -d "${DOTFILES_RESTORE_SOURCE:-/Volumes/DotfilesSecrets}" ]; then
  if bash "$DOTFILES/scripts/secrets-health.sh" >/dev/null 2>&1; then
    ok "mounted vault snapshot is valid and fresh"
  else
    warn "mounted vault snapshot is invalid or stale; run: make secrets-health"
  fi
else
  note "vault unmounted (normal after restore); mount it for day-2 freshness check: make secrets-health"
fi

if bash "$DOTFILES/scripts/link.sh" --check >/dev/null 2>&1; then
  ok "all managed symlinks healthy"
else
  warn "managed symlink drift detected; run: bash scripts/link.sh --check"
fi

if ! have python3; then
  warn "app preference snapshot audit skipped (python3 missing)"
elif [ ! -f "$DOTFILES/scripts/lib/plist_drift.py" ]; then
  warn "app preference snapshot audit unavailable (scripts/lib/plist_drift.py missing)"
elif [ ! -f "$DOTFILES/apps.tsv" ]; then
  warn "app preference snapshot audit unavailable (apps.tsv missing)"
elif run_with_timeout "$AUDIT_TIMEOUT" bash "$DOTFILES/scripts/audit-apps-drift.sh" --check --strict >/dev/null 2>&1; then
  ok "app preference snapshots match system state"
else
  status=$?
  if (( status == 124 )); then
    warn "app preference audit timed out after ${AUDIT_TIMEOUT}s"
  else
    warn "app preference snapshot drift detected; run: make apps-drift"
  fi
fi

printf '\nSummary: %d warning(s), %d failure(s)\n' "$WARNINGS" "$FAILURES"
if (( FAILURES > 0 || (STRICT && WARNINGS > 0) )); then
  exit 1
fi
