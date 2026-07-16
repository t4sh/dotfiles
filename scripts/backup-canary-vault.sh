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
DEST_PREFS="$DEST/preferences/io.canarymail.mac.plist"
DEST_REALMS="$DEST/realms"

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m  ✓\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[[ -d "$CONTAINER" ]] || die "Canary container not found — install Canary Mail first (Brewfile mas)"
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

info "backing up Canary Mail config to $DEST"
mkdir -p "$(dirname "$DEST_PREFS")" "$DEST_REALMS"

[[ -f "$PREFS_SRC" ]] || die "missing preferences: $PREFS_SRC"
cp -f "$PREFS_SRC" "$DEST_PREFS"
ok "preferences/io.canarymail.mac.plist"

for name in "${REALM_FILES[@]}"; do
  src="$DB_SRC/$name"
  [[ -f "$src" ]] || continue
  cp -f "$src" "$DEST_REALMS/$name"
  ok "realms/$name"

  # Realm sidecars evolve with Canary. Stage management/note state for every
  # declared realm instead of maintaining a second, PGP-only allowlist.
  for suffix in management note; do
    extra="$name.$suffix"
    src="$DB_SRC/$extra"
    [[ -e "$src" ]] || continue
    rm -rf "${DEST_REALMS:?}/$extra"
    cp -a "$src" "$DEST_REALMS/$extra"
    ok "realms/$extra"
  done
done

# Optional small LevelDB helpers for PGP domain/mailbox maps
for ldb in pgp.domain.ldb pgp.mailbox.ldb; do
  src="$DB_SRC/$ldb"
  [[ -d "$src" ]] || continue
  rm -rf "${DEST_REALMS:?}/$ldb"
  cp -a "$src" "$DEST_REALMS/$ldb"
  ok "realms/$ldb"
done

echo ""
ok "Canary config staged under ~/.secrets/apps/canary-mail/"
echo "  next: run make secrets-backup to write the encrypted sparseimage snapshot"
