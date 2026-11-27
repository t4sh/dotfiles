#!/usr/bin/env bash
# Windows uses native entry points; reject before any Unix-path mutation.
case "${OS:-}:$(uname -s)" in
  Windows_NT:*|*:MINGW*|*:MSYS*) echo 'This is a macOS workflow. On Windows run bin/dot.cmd help.' >&2; exit 2 ;;
esac
# Validate and restore the canonical ~/.secrets tree from a finalized vault
# snapshot. Check mode is read-only; mutation requires explicit --apply.
set -euo pipefail

MODE=check
case "${1:-}" in
  --check) shift ;;
  --apply) MODE=apply; shift ;;
  -h|--help)
    echo "usage: secrets-restore.sh [--check|--apply] [YYYYMMDD-HHMMSS]"
    exit 0
    ;;
esac

SOURCE_ROOT="${DOTFILES_RESTORE_SOURCE:-/Volumes/DotfilesSecrets}"
STAMP="${1:-}"
TARGET="${DOTFILES_SECRETS_DIR:-$HOME/.secrets}"

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m  ✓\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
has_dot_segment() {
  case "/${1#/}/" in
    *"/./"*|*"/../"*) return 0 ;;
    *) return 1 ;;
  esac
}

[[ "$SOURCE_ROOT" == /* && -d "$SOURCE_ROOT" ]] || die "vault snapshot root unavailable: $SOURCE_ROOT"
has_dot_segment "$SOURCE_ROOT" && die "vault snapshot root must not contain . or .. path components"
if [[ -z "$STAMP" ]]; then
  STAMP="$(find "$SOURCE_ROOT" -maxdepth 1 -type d \
    -name '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]' \
    -exec basename {} \; | LC_ALL=C sort | tail -n 1)"
fi
[[ "$STAMP" =~ ^[0-9]{8}-[0-9]{6}$ ]] || die "invalid finalized snapshot name: ${STAMP:-<none>}"

SNAPSHOT="$SOURCE_ROOT/$STAMP"
[[ -d "$SNAPSHOT" && ! -L "$SNAPSHOT" ]] || die "snapshot missing or is not a real directory: $SNAPSHOT"
if [[ -f "$SNAPSHOT/.dotfiles-snapshot.json" ]]; then
  SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
  python3 "$SCRIPT_DIR/vault-integrity.py" check "$SNAPSHOT"
fi

if [[ -n "${DOTFILES_RESTORE_SECRETS_SOURCE:-}" ]]; then
  SNAPSHOT_SECRETS="$DOTFILES_RESTORE_SECRETS_SOURCE"
elif [[ -d "$SNAPSHOT/payload/secrets" ]]; then
  SNAPSHOT_SECRETS="$SNAPSHOT/payload/secrets"
elif [[ -d "$SNAPSHOT$HOME/.secrets" ]]; then
  # Backward compatibility for absolute-path snapshots created by older runs.
  SNAPSHOT_SECRETS="$SNAPSHOT$HOME/.secrets"
else
  legacy_candidates=()
  if [[ -d "$SNAPSHOT/Users" ]]; then
    while IFS= read -r -d '' candidate; do
      legacy_candidates+=("$candidate")
    done < <(find "$SNAPSHOT/Users" -mindepth 2 -maxdepth 2 -type d -name .secrets -print0)
  fi
  case "${#legacy_candidates[@]}" in
    1) SNAPSHOT_SECRETS="${legacy_candidates[0]}" ;;
    0) die "canonical secrets payload missing: $SNAPSHOT/payload/secrets" ;;
    *) die "ambiguous legacy secrets payloads under $SNAPSHOT/Users; set DOTFILES_RESTORE_SECRETS_SOURCE explicitly" ;;
  esac
fi
has_dot_segment "$SNAPSHOT_SECRETS" && die "secrets restore source must not contain . or .. path components"
[[ -d "$SNAPSHOT_SECRETS" ]] || die "canonical secrets payload missing: $SNAPSHOT_SECRETS"

if ! file_count="$(python3 - "$SNAPSHOT" "$SNAPSHOT_SECRETS" <<'PY'
import os
import stat
import sys


def fail(reason):
    print(f"invalid secrets restore source: {reason}", file=sys.stderr)
    raise SystemExit(1)


snapshot = os.path.abspath(sys.argv[1])
payload = os.path.abspath(sys.argv[2])

try:
    snapshot_mode = os.lstat(snapshot).st_mode
except OSError:
    fail("snapshot directory is unavailable")
if not stat.S_ISDIR(snapshot_mode):
    fail("snapshot root is not a real directory")

# For in-snapshot payloads, inspect each component between the snapshot and
# the selected root. This catches a link in an ancestor even though walking
# the final path alone would follow it. Explicit custom sources outside the
# snapshot remain supported; their selected root and descendants are checked.
try:
    relative = os.path.relpath(payload, snapshot)
    contained = os.path.commonpath((snapshot, payload)) == snapshot
except ValueError:
    contained = False
    relative = ""

if contained:
    current = snapshot
    for component in (() if relative == "." else relative.split(os.sep)):
        current = os.path.join(current, component)
        try:
            mode = os.lstat(current).st_mode
        except OSError:
            fail("selected payload path is unavailable")
        if stat.S_ISLNK(mode):
            fail("selected snapshot or payload path contains a symlink")
        if not stat.S_ISDIR(mode):
            fail("selected payload path contains a non-directory ancestor")

try:
    root_mode = os.lstat(payload).st_mode
except OSError:
    fail("selected payload is unavailable")
if not stat.S_ISDIR(root_mode):
    fail("selected payload root is not a real directory")

file_count = 0
pending = [payload]
while pending:
    directory = pending.pop()
    try:
        with os.scandir(directory) as entries:
            for entry in entries:
                try:
                    mode = entry.stat(follow_symlinks=False).st_mode
                except OSError:
                    fail("payload changed during validation")
                if stat.S_ISLNK(mode):
                    fail("payload contains a symlink")
                if stat.S_ISDIR(mode):
                    pending.append(entry.path)
                elif stat.S_ISREG(mode):
                    file_count += 1
                else:
                    fail("payload contains a special file")
    except OSError:
        fail("payload could not be read")

if file_count == 0:
    fail("secrets payload is empty")
print(file_count)
PY
)"; then
  die "secrets payload validation failed"
fi
size="$(du -sh "$SNAPSHOT_SECRETS" | awk '{print $1}')"
info "snapshot: $STAMP"
ok "validated canonical secrets payload ($file_count file(s), $size)"

if [[ "$MODE" == check ]]; then
  info "read-only check complete; apply explicitly with: make secrets-restore-apply"
  exit 0
fi

[[ "$TARGET" == "$HOME/.secrets" || -n "${DOTFILES_SECRETS_DIR:-}" ]] || die "refusing unexpected restore target: $TARGET"
[[ "$TARGET" == /* && -n "${TARGET//\//}" ]] || die "restore target must be an absolute non-root path: $TARGET"
[[ "$TARGET" != *'/../'* && "$TARGET" != */.. && "$TARGET" != *'/./'* && "$TARGET" != */. ]] || \
  die "restore target must not contain dot segments: $TARGET"
TARGET_PARENT="$(dirname "$TARGET")"
TARGET_NAME="$(basename "$TARGET")"
[[ -d "$TARGET_PARENT" ]] || die "restore target parent does not exist: $TARGET_PARENT"
STAGE="$TARGET_PARENT/.$TARGET_NAME.restore-stage.$$"
ROLLBACK="$TARGET_PARENT/.$TARGET_NAME.restore-rollback.$$"
[[ ! -e "$STAGE" && ! -e "$ROLLBACK" ]] || die "restore staging path already exists; inspect and remove it manually"
PUBLISHING=0
HAD_TARGET=0

cleanup() {
  local status=$?
  trap - EXIT HUP INT TERM
  if [[ -e "$ROLLBACK" ]]; then
    rm -rf -- "${TARGET:?}"
    mv "$ROLLBACK" "$TARGET"
  elif (( PUBLISHING && ! HAD_TARGET )); then
    rm -rf -- "${TARGET:?}"
  fi
  rm -rf -- "$STAGE" "$ROLLBACK"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

info "staging $TARGET"
mkdir -p "$STAGE"
rsync -a --delete "$SNAPSHOT_SECRETS/" "$STAGE/"
[[ "$(find "$STAGE" -type f | wc -l | tr -d '[:space:]')" == "$file_count" ]] || \
  die "staged restore file count differs from validated snapshot"
chmod 700 "$STAGE"

[[ -e "$TARGET" ]] && HAD_TARGET=1
PUBLISHING=1
if (( HAD_TARGET )); then
  mv "$TARGET" "$ROLLBACK"
fi
mv "$STAGE" "$TARGET"
PUBLISHING=0
rm -rf -- "$ROLLBACK"
ROLLBACK=""
ok "restored $TARGET from $STAMP"
info "next: make secrets-pass-import && make post-vault"
