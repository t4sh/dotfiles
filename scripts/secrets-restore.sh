#!/usr/bin/env bash
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

[[ "$SOURCE_ROOT" == /* && -d "$SOURCE_ROOT" ]] || die "vault snapshot root unavailable: $SOURCE_ROOT"
if [[ -z "$STAMP" ]]; then
  STAMP="$(find "$SOURCE_ROOT" -maxdepth 1 -type d \
    -name '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]' \
    -exec basename {} \; | LC_ALL=C sort | tail -n 1)"
fi
[[ "$STAMP" =~ ^[0-9]{8}-[0-9]{6}$ ]] || die "invalid finalized snapshot name: ${STAMP:-<none>}"

SNAPSHOT="$SOURCE_ROOT/$STAMP"
[[ -d "$SNAPSHOT" ]] || die "snapshot not found: $SNAPSHOT"

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
[[ -d "$SNAPSHOT_SECRETS" ]] || die "canonical secrets payload missing: $SNAPSHOT_SECRETS"

file_count="$(find "$SNAPSHOT_SECRETS" -type f | wc -l | tr -d '[:space:]')"
(( file_count > 0 )) || die "secrets payload is empty: $SNAPSHOT_SECRETS"
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
