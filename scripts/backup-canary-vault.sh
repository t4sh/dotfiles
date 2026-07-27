#!/usr/bin/env bash
# Copy Canary Mail config (realms + preferences) into ~/.secrets/apps/canary-mail/.
# Excludes mail cache (emls2.ldb, caches) — vault stays ~5MB, not ~1.6GB.
#
# Usage: bash scripts/backup-canary-vault.sh
# Then run: make secrets-backup
set -euo pipefail

CONTAINER="$HOME/Library/Containers/io.canarymail.mac/Data/Library"
PREFS_SRC="$CONTAINER/Preferences/io.canarymail.mac.plist"
DB_SRC="$CONTAINER/Application Support/CanaryDB"
DEST="$HOME/.secrets/apps/canary-mail"
DEST_PARENT="$(dirname "$DEST")"
STAGE=""

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m  ✓\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[[ -d "$CONTAINER" ]] || die "Canary container not found — install and launch Canary Mail first"
if pgrep -xq "Canary Mail" 2>/dev/null || pgrep -xf ".*Canary Mail.*" 2>/dev/null; then
  die "Canary Mail is running — quit it before copying realm state"
fi

REALM_FILES=(
  accounts.v2.realm
  encrypted.realm
  pgp.v2.realm
  enterprise.realm
  unsubscribe.realm
  appIntegration.realm
  calendar.events.realm
)

cleanup() {
  local status=$?
  [[ -n "$STAGE" && -d "$STAGE" ]] && rm -rf -- "$STAGE"
  return "$status"
}
trap cleanup EXIT

info "backing up Canary Mail config to $DEST"
mkdir -p "$DEST_PARENT"
STAGE="$(mktemp -d "$DEST_PARENT/.canary-mail.tmp.XXXXXX")"
STAGE_PREFS="$STAGE/preferences/io.canarymail.mac.plist"
STAGE_REALMS="$STAGE/realms"
mkdir -p "$(dirname "$STAGE_PREFS")" "$STAGE_REALMS"

[[ -f "$PREFS_SRC" ]] || die "missing preferences: $PREFS_SRC"
cp -f "$PREFS_SRC" "$STAGE_PREFS"
ok "preferences/io.canarymail.mac.plist"

for name in "${REALM_FILES[@]}"; do
  src="$DB_SRC/$name"
  [[ -f "$src" ]] || continue
  cp -f "$src" "$STAGE_REALMS/$name"
  ok "realms/$name"

  # Realm sidecars evolve with Canary. Stage management/note state for every
  # declared realm instead of maintaining a second, PGP-only allowlist.
  for suffix in management note; do
    extra="$name.$suffix"
    src="$DB_SRC/$extra"
    [[ -e "$src" ]] || continue
    cp -a "$src" "$STAGE_REALMS/$extra"
    ok "realms/$extra"
  done
done

# Optional small LevelDB helpers for PGP domain/mailbox maps.
for ldb in pgp.domain.ldb pgp.mailbox.ldb; do
  src="$DB_SRC/$ldb"
  [[ -d "$src" ]] || continue
  cp -a "$src" "$STAGE_REALMS/$ldb"
  ok "realms/$ldb"
done

if [[ -e "$DEST" ]]; then
  command -v python3 >/dev/null 2>&1 || die "python3 is required for atomic Canary backup replacement"
  # macOS renamex_np(RENAME_SWAP) atomically exchanges two sibling directories.
  # After the swap, DEST is the complete new snapshot and STAGE holds the old one.
  STAGE_PATH="$STAGE" DEST_PATH="$DEST" python3 <<'PY'
import ctypes
import os

libc = ctypes.CDLL(None, use_errno=True)
renamex_np = libc.renamex_np
renamex_np.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
renamex_np.restype = ctypes.c_int
RENAME_SWAP = 0x00000002
src = os.fsencode(os.environ["STAGE_PATH"])
dst = os.fsencode(os.environ["DEST_PATH"])
if renamex_np(src, dst, RENAME_SWAP) != 0:
    error = ctypes.get_errno()
    raise OSError(error, os.strerror(error), os.environ["DEST_PATH"])
PY
  rm -rf -- "$STAGE"
else
  mv "$STAGE" "$DEST"
fi
STAGE=""
trap - EXIT

echo ""
ok "Canary config replaced under ~/.secrets/apps/canary-mail/"
echo "  next: run make secrets-backup to write the encrypted sparseimage snapshot"
