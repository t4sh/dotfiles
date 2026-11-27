#!/usr/bin/env bash
# Windows uses native entry points; reject before any Unix-path mutation.
case "${OS:-}:$(uname -s)" in
  Windows_NT:*|*:MINGW*|*:MSYS*) echo 'This is a macOS workflow. On Windows run bin/dot.cmd help.' >&2; exit 2 ;;
esac
# Capture repo-managed preferences into a staged tree, validate it, then publish
# the complete snapshot transactionally. Failed publication attempts to restore
# unchanged paths and keeps recovery data for anything that needs inspection.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
SOURCE_DOTFILES="$DOTFILES"
MANIFEST="$DOTFILES/apps.tsv"
BACKUP_LOCK="$HOME/.dotfiles-backup-apps.lock"

# A killed run cannot clean up after itself. A journal means publication had
# begun: saved snapshots may be missing, and a new capture would hide that.
refuse_unfinished_publication() {
  local leftover
  for leftover in "$DOTFILES"/.backup-rollback.*; do
    [[ -d "$leftover" && ! -L "$leftover" && -e "$leftover/journal.jsonl" ]] || continue
    {
      echo "error: an earlier backup left recovery data in $leftover"
      echo "  Its publication was interrupted or its rollback could not finish."
      echo "  Make sure no backup is still running, then undo a partial publication with:"
      printf '    python3 %q rollback --destination %q --rollback %q\n' \
        "$SOURCE_DOTFILES/scripts/publish-app-backup.py" "$DOTFILES" "$leftover"
      echo "  Move any reported editor saves to safety and retry rollback until it succeeds."
      echo "  Verify the recovered files before removing this recovery directory and rerunning backup."
    } >&2
    exit 1
  done
}

# make backup asks this first, so the refusal comes before it saves the macOS policy.
if [[ "${1:-}" == --recovery-check ]]; then
  # Recovery data belongs to a backup that is publishing right now while that
  # backup holds the lock; only data no run owns is left over. Without a lock
  # file no backup has run, and the probe must not create one.
  if [[ -e "$BACKUP_LOCK" && ! -L "$BACKUP_LOCK" ]]; then
    lock_probe=0
    lockf -k -s -t 0 "$BACKUP_LOCK" true 2>/dev/null || lock_probe=$?
    if (( lock_probe == 75 )); then
      echo "error: another app backup is already running (or a policy capture holds its lock)" >&2
      exit 1
    fi
  fi
  refuse_unfinished_publication
  exit 0
fi

# Review answers come from the terminal. Refuse before capturing anything.
if [[ "${DOTFILES_REVIEW_MAC_PREFERENCES:-0}" == 1 && ! -t 0 ]]; then
  echo "error: preference review needs a terminal; rerun dotbackup in a terminal, or use make backup OVERRIDE=1 to adopt every change" >&2
  exit 1
fi

# Serialize backup captures and publication. The lock file intentionally stays
# in HOME so lockf can safely arbitrate competing starts without an unlink race.
if [[ "${DOTFILES_BACKUP_LOCK_HELD:-0}" != "1" ]]; then
  if [[ -L "$BACKUP_LOCK" ]]; then
    echo "error: refusing symlinked backup lock: $BACKUP_LOCK" >&2
    exit 1
  fi
  lock_status=0
  backup_umask="$(umask)"
  (
    umask 077
    lockf -k -s -t 0 "$BACKUP_LOCK" \
      env DOTFILES_BACKUP_LOCK_HELD=1 DOTFILES_BACKUP_UMASK="$backup_umask" \
      bash "$0" "$@"
  ) || lock_status=$?
  if (( lock_status == 75 )); then
    echo "error: another app backup is already running (or a policy capture holds its lock)" >&2
  elif (( lock_status != 0 )); then
    echo "error: app backup command failed (exit $lock_status); see the first error above" >&2
  fi
  exit "$lock_status"
fi
if [[ -n "${DOTFILES_BACKUP_UMASK:-}" ]]; then
  umask "$DOTFILES_BACKUP_UMASK"
  unset DOTFILES_BACKUP_UMASK
fi

# Checked again under the lock: a run that finished meanwhile may have left some.
refuse_unfinished_publication
# Other leftovers hold captures taken before sanitation. Report them and leave
# removal to the operator: a run whose lock wrapper died could still own one.
for leftover in "$DOTFILES"/.backup-stage.* "$DOTFILES"/.backup-base.* "$DOTFILES"/.backup-rollback.*; do
  [[ -d "$leftover" && ! -L "$leftover" ]] || continue
  echo "  ⚠ scratch data from an interrupted backup remains: $leftover" >&2
  echo "    It can hold unsanitized captures; remove it once no backup is running." >&2
done

STAGE="$(mktemp -d "$DOTFILES/.backup-stage.XXXXXX")"
BASE="$(mktemp -d "$DOTFILES/.backup-base.XXXXXX")"
ROLLBACK="$(mktemp -d "$DOTFILES/.backup-rollback.XXXXXX")"
PUBLISHING=0
TARGETS=(apps macos services Brewfile)

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  ⚠\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

cleanup() {
  local status=$? rollback_failed=0
  trap - EXIT HUP INT TERM
  trap '' HUP INT TERM
  if (( PUBLISHING )); then
    warn "backup publication failed; restoring unchanged published paths"
    python3 "$SOURCE_DOTFILES/scripts/publish-app-backup.py" rollback \
      --destination "$DOTFILES" --rollback "$ROLLBACK" || rollback_failed=1
  fi
  rm -rf -- "$STAGE" "$BASE"
  if (( rollback_failed )); then
    echo "error: rollback incomplete; preserve recovery data in $ROLLBACK" >&2
    status=1
  else
    rm -rf -- "$ROLLBACK"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# Some native writers prompt or fail when their output already exists with a
# read-only mode or ACL. Give them a fresh file, then keep the seeded metadata.
CAPTURE="$(mktemp -d "$STAGE/.capture.XXXXXX")"
install_capture() {
  local relative="$1"
  mkdir -p "$(dirname "$STAGE/$relative")"
  python3 "$SOURCE_DOTFILES/scripts/backup_metadata.py" "$CAPTURE/$relative" "$STAGE/$relative"
  rm -f "$CAPTURE/$relative"
}

capture_string_plist() {
  local relative="$1" key="$2" value="$3" output="$CAPTURE/$1"
  mkdir -p "$(dirname "$output")"
  plutil -create xml1 "$output"
  plutil -insert "$key" -string "$value" "$output"
  install_capture "$relative"
}

export_nonempty_defaults() {
  local domain="$1" output="$2" view
  defaults export "$domain" "$output" 2>/dev/null &&
    view="$(plutil -p "$output" 2>/dev/null)" &&
    rg -q '[^[:space:]{}]' <<< "$view"
}

bash "$DOTFILES/scripts/validate-manifests.sh" apps

capture_args=()
publish_args=()
for target in "${TARGETS[@]}"; do
  capture_args+=(--target "$target")
  publish_args+=(--target "$target")
done
python3 "$SOURCE_DOTFILES/scripts/publish-app-backup.py" record-directories \
  --destination "$DOTFILES" --base "$BASE" "${capture_args[@]}"

# Keep the source quarantine record. A regular macOS cp -Rp can reissue it
# during capture, causing a false same-path conflict against the original.
copy_snapshot() {
  if [[ "$OSTYPE" == darwin* && ! -L "$1" ]]; then
    ditto --rsrc --extattr --acl --qtn "$1" "$2"
  else
    cp -Rp "$1" "$2"
  fi
}

# Seed the complete managed roots so unavailable optional apps retain their last
# known-good snapshot in the staged candidate.
for target in "${TARGETS[@]}"; do
  [[ -e "$DOTFILES/$target" ]] || die "managed backup target missing: $DOTFILES/$target"
  mkdir -p "$STAGE/$(dirname "$target")" "$BASE/$(dirname "$target")"
  # Capture the original tree once, preserving metadata; stage from that exact
  # capture so edits during the copy window are detected at publication.
  copy_snapshot "$DOTFILES/$target" "$BASE/$target"
  copy_snapshot "$BASE/$target" "$STAGE/$target"
done
cp "$DOTFILES/.node-version" "$STAGE/.node-version"
# Compare against a sanitized copy of the prior snapshots, never reintroducing
# fields removed by current sanitation rules when retaining equivalent bytes.
PREVIOUS="$STAGE/.previous"
mkdir -p "$PREVIOUS"
for target in apps macos services .node-version; do
  copy_snapshot "$STAGE/$target" "$PREVIOUS/$target"
done

info "capturing app preferences into a staged snapshot"
captured=0
skipped=0
iina_captured=0
while IFS=$'\t' read -r domain label plist _; do
  case "${domain:-}" in ''|'#'*) continue ;; esac
  # These public manifest rows remain documentation-only pending a separate
  # privacy review; public backup does not capture Services or device domains.
  case "$domain" in
    pbs|com.apple.AppleMultitouchTrackpad|com.apple.driver.AppleBluetoothMultitouch.trackpad|com.apple.AppleMultitouchMouse|com.apple.driver.AppleBluetoothMultitouch.mouse) continue ;;
  esac
  mkdir -p "$(dirname "$STAGE/$plist")"
  mkdir -p "$(dirname "$CAPTURE/$plist")"
  # A never-configured domain may export successfully as an empty dictionary.
  # Keep its prior snapshot instead of replacing it with an empty plist.
  if export_nonempty_defaults "$domain" "$CAPTURE/$plist"; then
    install_capture "$plist"
    ok "$label"
    captured=$((captured + 1))
    [[ "$domain" != com.colliderli.iina ]] || iina_captured=1
  else
    rm -f "$CAPTURE/$plist"
    warn "$label not captured (app/domain unavailable; prior snapshot retained)"
    skipped=$((skipped + 1))
  fi
done < "$MANIFEST"
info "defaults snapshots: $captured captured, $skipped retained"

# IINA uses the same Screengrabs folder as the saved macOS screenshot policy.
# Its machine/account path is restored from that policy, not copied into apps/.
if (( iina_captured )); then
  iina_capture_dir="$(plutil -extract screenShotFolder raw -o - "$STAGE/apps/iina/iina.plist" 2>/dev/null || true)"
  saved_capture_dir="$(python3 "$SOURCE_DOTFILES/scripts/macos-preferences.py" capture-dir)"
  live_capture_dir="$saved_capture_dir"
  [[ -n "$iina_capture_dir" && ( "$iina_capture_dir" == "$saved_capture_dir" || "$iina_capture_dir" == "$live_capture_dir" ) ]] ||
    die 'IINA Screengrabs folder differs from saved macOS screenshot location; reconcile it before backup'
  ok 'IINA Screengrabs folder matches saved macOS screenshot location'
fi

DATO_PRIMARY="$HOME/Library/Containers/com.sindresorhus.Dato/Data/Library/Preferences/com.sindresorhus.Dato.plist"
if DATO_FORMAT="$(plutil -extract dateTimeFormat raw -o - "$DATO_PRIMARY" 2>/dev/null)"; then
  capture_string_plist apps/dato/display.plist dateTimeFormat "$DATO_FORMAT"
  ok "Dato custom date/time format (other primary preferences are not captured)"
else
  warn "Dato custom date/time format unavailable (prior snapshot retained)"
fi

dock_capture="$STAGE/.dock-backup.plist"
defaults export com.apple.dock "$dock_capture" 2>/dev/null || \
  die "Dock layout export failed; staged snapshot discarded"
ok "Dock layout"
mkdir -p "$CAPTURE/apps/terminal"
if export_nonempty_defaults com.apple.Terminal "$CAPTURE/apps/terminal/terminal.plist"; then
  install_capture apps/terminal/terminal.plist
  ok "Terminal.app profiles"
else
  warn "Terminal.app profiles not captured (prior snapshot retained)"
fi

for workflow in "$DOTFILES"/services/*.workflow; do
  [[ -e "$workflow" ]] || continue
  name="$(basename "$workflow")"
  source="$HOME/Library/Services/$name"
  [[ -d "$source" ]] || continue
  rm -rf -- "$STAGE/services/$name"
  copy_snapshot "$source" "$STAGE/services/$name"
  ok "Automator workflow $name"
done

DOTFILES="$STAGE" bash "$SOURCE_DOTFILES/scripts/sanitize-app-prefs.sh" "$dock_capture"
rm -f -- "$dock_capture"
DOTFILES="$PREVIOUS" bash "$SOURCE_DOTFILES/scripts/sanitize-app-prefs.sh" --comparison
if [[ "${DOTFILES_REVIEW_MAC_PREFERENCES:-0}" == 1 ]]; then
  review_args=(--review-macos --base "$BASE")
  dock_path=macos/dock-backup.plist
  if git -C "$SOURCE_DOTFILES" ls-files --error-unmatch -- "$dock_path" >/dev/null 2>&1 &&
     ! git -C "$SOURCE_DOTFILES" diff --quiet -- "$dock_path"; then
    git -C "$SOURCE_DOTFILES" show ":$dock_path" > "$PREVIOUS/index-dock.plist"
    review_args+=(--indexed-dock "$PREVIOUS/index-dock.plist")
  fi
  python3 "$SOURCE_DOTFILES/scripts/stabilize-plist-backups.py" "$STAGE" "$PREVIOUS" "${review_args[@]}"
else
  python3 "$SOURCE_DOTFILES/scripts/stabilize-plist-backups.py" "$STAGE" "$PREVIOUS"
fi
ok "sanitized portable app prefs"
DOTFILES="$SOURCE_DOTFILES" BREWFILE="$SOURCE_DOTFILES/Brewfile" \
  DOTFILES_BREWFILE_PRESERVE_EMPTY_KINDS=1 \
  bash "$SOURCE_DOTFILES/scripts/brewfile.sh" dump "$CAPTURE/Brewfile"
OVERRIDE="${OVERRIDE:-0}" python3 "$SOURCE_DOTFILES/scripts/brewfile-review.py" \
  --saved "$SOURCE_DOTFILES/Brewfile" \
  --candidate "$CAPTURE/Brewfile"
install_capture Brewfile
ok "Brewfile"
DOTFILES="$STAGE" bash "$SOURCE_DOTFILES/scripts/audit-app-prefs.sh"
rm -rf -- "$PREVIOUS" "$CAPTURE"
command -v gitleaks >/dev/null 2>&1 || die "gitleaks is required before publishing app snapshots (install with brew install gitleaks)"
gitleaks dir "$STAGE" --config "$SOURCE_DOTFILES/.gitleaks.toml" --redact --no-banner || \
  die "gitleaks rejected the staged app snapshot; prior repo snapshot preserved"

info "publishing changed snapshot paths"
PUBLISHING=1
python3 "$SOURCE_DOTFILES/scripts/publish-app-backup.py" publish \
  --base "$BASE" --candidate "$STAGE" --destination "$DOTFILES" \
  --rollback "$ROLLBACK" "${publish_args[@]}"
PUBLISHING=0
rm -rf -- "$ROLLBACK"
ROLLBACK=""
ok "changed backup paths published"

cat <<'EOF'

Additional private backups:
  - make backup also captures full Dato, Shottr and Deskflow configuration into ~/.secrets.
  - Canary Mail: make backup-canary
  - Transmit / Raycast: export into ~/.secrets/apps/
  - Finish with make secrets-backup to publish an encrypted recovery DMG.
EOF
