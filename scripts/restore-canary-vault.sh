#!/usr/bin/env bash
# Restore Canary Mail config from ~/.secrets/apps/canary-mail/ into the sandbox.
# The shared gate quits/reopens Canary Mail because realm files lock while open.
# Managed live paths absent from the vault snapshot are removed transactionally.
#
# Usage: bash scripts/restore-canary-vault.sh
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
CONTAINER="$HOME/Library/Containers/io.canarymail.mac/Data/Library"
PREFS_DST="$CONTAINER/Preferences/io.canarymail.mac.plist"
DB_DST="$CONTAINER/Application Support/CanaryDB"
SRC="$HOME/.secrets/apps/canary-mail"
SRC_PREFS="$SRC/preferences/io.canarymail.mac.plist"
SRC_REALMS="$SRC/realms"
MANAGED_REALMS="$DOTFILES/config/canary-managed-realms.tsv"
STAGE=""

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  ⚠\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[[ -f "$SRC_PREFS" && -d "$SRC_REALMS" ]] || die \
  "incomplete vault copy at $SRC — expected preferences/io.canarymail.mac.plist and realms/; run: make backup-canary"
# Preflight before the running-app gate so a missing container/python3 cannot
# quit Canary and then exit without the reopen trap.
[[ -d "$CONTAINER" ]] || die "Canary container not found"
command -v python3 >/dev/null 2>&1 || die "python3 is required for transactional Canary restore"
[[ -f "$MANAGED_REALMS" ]] || die "managed realm manifest missing: $MANAGED_REALMS"

MANAGED_REALM_NAMES=()
while IFS= read -r name || [[ -n "$name" ]]; do
  name="${name%%#*}"
  name="${name#"${name%%[![:space:]]*}"}"
  name="${name%"${name##*[![:space:]]}"}"
  [[ -z "$name" ]] && continue
  [[ "$name" != */* && "$name" != "." && "$name" != ".." ]] || \
    die "managed realm entries must be basenames: $name"
  MANAGED_REALM_NAMES+=("$name")
done < "$MANAGED_REALMS"
((${#MANAGED_REALM_NAMES[@]} > 0)) || die "managed realm manifest is empty: $MANAGED_REALMS"

# shellcheck source=scripts/lib/running-app-gate.sh
source "$DOTFILES/scripts/lib/running-app-gate.sh"

cleanup() {
  local status=$?
  if [[ -n "$STAGE" && -d "$STAGE" ]]; then
    if [[ -f "$STAGE/.publish-pending" ]]; then
      warn "Canary rollback was incomplete; preserved recovery state at $STAGE"
    else
      rm -rf -- "$STAGE"
    fi
  fi
  restore_reopen_apps || true
  return "$status"
}
trap cleanup EXIT

# Shared gate: warn, quit, refuse unless FORCE; EXIT trap reopens what we quit.
restore_running_app_gate "Canary Mail:Canary Mail"

info "restoring Canary Mail from $SRC"
STAGE="$(mktemp -d "$CONTAINER/.canary-restore.XXXXXX")"
STAGE_PREFS="$STAGE/preferences/io.canarymail.mac.plist"
STAGE_REALMS="$STAGE/realms"
STAGE_REMOVED="$STAGE/removed"
mkdir -p "$(dirname "$STAGE_PREFS")" "$STAGE_REALMS" "$STAGE_REMOVED"
STAGED_PATHS=()
LIVE_PATHS=()
REMOVE_LIVE_PATHS=()

path_in_list() {
  local needle="$1" item
  for item in "${LIVE_PATHS[@]+"${LIVE_PATHS[@]}"}"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

if [[ -f "$SRC_PREFS" ]]; then
  cp -p "$SRC_PREFS" "$STAGE_PREFS"
  STAGED_PATHS+=("$STAGE_PREFS")
  LIVE_PATHS+=("$PREFS_DST")
fi

if [[ -d "$SRC_REALMS" ]]; then
  shopt -s nullglob
  for src in "$SRC_REALMS"/*; do
    base="${src##*/}"
    [[ -e "$src" ]] || continue
    cp -a "$src" "$STAGE_REALMS/$base"
    STAGED_PATHS+=("$STAGE_REALMS/$base")
    LIVE_PATHS+=("$DB_DST/$base")
  done
  shopt -u nullglob
fi

# Converge managed inventory: remove live managed paths absent from the snapshot.
for name in "${MANAGED_REALM_NAMES[@]}"; do
  for candidate in "$name" "$name.management" "$name.note"; do
    live="$DB_DST/$candidate"
    path_in_list "$live" && continue
    [[ -e "$live" ]] || continue
    REMOVE_LIVE_PATHS+=("$live")
  done
done

for ldb in pgp.domain.ldb pgp.mailbox.ldb; do
  live="$DB_DST/$ldb"
  path_in_list "$live" && continue
  [[ -e "$live" ]] || continue
  REMOVE_LIVE_PATHS+=("$live")
done

((${#STAGED_PATHS[@]} > 0 || ${#REMOVE_LIVE_PATHS[@]} > 0)) \
  || die "vault copy contains no restorable Canary paths"
mkdir -p "$(dirname "$PREFS_DST")" "$DB_DST"
touch "$STAGE/.publish-pending"

# Publish present paths, then remove managed live paths absent from the snapshot.
# Removals are staged under STAGE/removed for rollback. All pairs share a
# filesystem with the Canary container so renamex_np(RENAME_SWAP) works.
CANARY_STAGE="$STAGE" python3 - \
  "${STAGED_PATHS[@]+"${STAGED_PATHS[@]}"}" -- \
  "${LIVE_PATHS[@]+"${LIVE_PATHS[@]}"}" -- \
  "${REMOVE_LIVE_PATHS[@]+"${REMOVE_LIVE_PATHS[@]}"}" <<'PY'
import ctypes
import os
import sys

args = sys.argv[1:]
separators = [i for i, value in enumerate(args) if value == "--"]
if len(separators) != 2:
    raise SystemExit("invalid Canary publish argument layout")
first, second = separators
sources = args[:first]
destinations = args[first + 1 : second]
removals = args[second + 1 :]
if len(sources) != len(destinations):
    raise SystemExit("invalid Canary publish path list")

libc = ctypes.CDLL(None, use_errno=True)
renamex_np = libc.renamex_np
renamex_np.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
renamex_np.restype = ctypes.c_int
RENAME_SWAP = 0x00000002

def swap(source: str, destination: str) -> None:
    if renamex_np(os.fsencode(source), os.fsencode(destination), RENAME_SWAP) != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), destination)

completed = []
fail_after = int(os.environ.get("DOTFILES_CANARY_TEST_FAIL_AFTER", "-1"))
removed_dir = os.path.join(os.environ["CANARY_STAGE"], "removed")
os.makedirs(removed_dir, exist_ok=True)

try:
    op_index = 0
    for source, destination in zip(sources, destinations):
        if op_index == fail_after:
            raise OSError("injected Canary publish failure")
        if os.path.lexists(destination):
            swap(source, destination)
            completed.append(("swap", source, destination))
        else:
            os.rename(source, destination)
            completed.append(("new", source, destination))
        op_index += 1

    for live in removals:
        if op_index == fail_after:
            raise OSError("injected Canary publish failure")
        if not os.path.lexists(live):
            op_index += 1
            continue
        backup = os.path.join(removed_dir, f"{op_index}-{os.path.basename(live)}")
        os.rename(live, backup)
        completed.append(("remove", backup, live))
        op_index += 1
except BaseException as publish_error:
    rollback_errors = []
    for operation, source, destination in reversed(completed):
        try:
            if operation == "swap":
                swap(source, destination)
            elif operation == "new":
                os.rename(destination, source)
            else:  # remove — source is staged backup, destination is live path
                os.rename(source, destination)
        except BaseException as rollback_error:
            rollback_errors.append(str(rollback_error))
    if rollback_errors:
        raise RuntimeError(
            f"publish failed ({publish_error}); rollback also failed: "
            + "; ".join(rollback_errors)
        ) from publish_error
    os.unlink(os.path.join(os.environ["CANARY_STAGE"], ".publish-pending"))
    raise

os.unlink(os.path.join(os.environ["CANARY_STAGE"], ".publish-pending"))
PY

for path in "${LIVE_PATHS[@]+"${LIVE_PATHS[@]}"}"; do
  ok "${path#"$CONTAINER"/}"
done
for path in "${REMOVE_LIVE_PATHS[@]+"${REMOVE_LIVE_PATHS[@]}"}"; do
  ok "removed stale ${path#"$CONTAINER"/}"
done

echo ""
ok "Canary restore complete (re-auth accounts if prompted)"
