#!/usr/bin/env bash
# Publish immutable, encrypted APFS/UDZO recovery images from the secrets manifest.
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
VOLNAME="DotfilesSecrets"
KC_SERVICE="DotfilesSecretsVault"
LOCAL_DIR="${DOTFILES_LOCAL_DIR:-$HOME/.dotfiles-local}"
MANIFEST="${DOTFILES_BACKUP_MANIFEST:-$LOCAL_DIR/backup.manifest}"
DEST_CACHE="$LOCAL_DIR/backup.destination"
RECOVERY_ACK="$LOCAL_DIR/vault-recovery.confirmed"
KEEP="${DOTFILES_BACKUP_KEEP:-10}"
STAMP="$(date +%Y%m%d-%H%M%S)"
SECRETS_DIR="${DOTFILES_SECRETS_DIR:-$HOME/.secrets}"
ARTIFACT_PREFIX="DotfilesSecrets-"
LEGACY_NAME="DotfilesSecrets.sparseimage"

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  ⚠\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$KEEP" =~ ^[1-9][0-9]*$ ]] || die "DOTFILES_BACKUP_KEEP must be a positive integer (got: $KEEP)"
[[ -f "$MANIFEST" ]] || die "manifest not found: $MANIFEST
  create it at $MANIFEST (or set \$DOTFILES_BACKUP_MANIFEST)
  see scripts/backup-manifest.example for the format"

expand_manifest_path() {
  local value="$1"
  # shellcheck disable=SC2088,SC2016
  case "$value" in
    '~') printf '%s' "$HOME" ;;
    '~/'*) printf '%s/%s' "$HOME" "${value#\~/}" ;;
    '$HOME') printf '%s' "$HOME" ;;
    '$HOME/'*) printf '%s/%s' "$HOME" "${value#\$HOME/}" ;;
    '${HOME}') printf '%s' "$HOME" ;;
    '${HOME}/'*) printf '%s/%s' "$HOME" "${value#\$\{HOME\}/}" ;;
    '$DOTFILES_SECRETS_DIR') printf '%s' "$SECRETS_DIR" ;;
    '$DOTFILES_SECRETS_DIR/'*) printf '%s/%s' "$SECRETS_DIR" "${value#\$DOTFILES_SECRETS_DIR/}" ;;
    '${DOTFILES_SECRETS_DIR}') printf '%s' "$SECRETS_DIR" ;;
    '${DOTFILES_SECRETS_DIR}/'*) printf '%s/%s' "$SECRETS_DIR" "${value#\$\{DOTFILES_SECRETS_DIR\}/}" ;;
    '$DOTFILES_LOCAL_DIR') printf '%s' "$LOCAL_DIR" ;;
    '$DOTFILES_LOCAL_DIR/'*) printf '%s/%s' "$LOCAL_DIR" "${value#\$DOTFILES_LOCAL_DIR/}" ;;
    '${DOTFILES_LOCAL_DIR}') printf '%s' "$LOCAL_DIR" ;;
    '${DOTFILES_LOCAL_DIR}/'*) printf '%s/%s' "$LOCAL_DIR" "${value#\$\{DOTFILES_LOCAL_DIR\}/}" ;;
    *'$'* | *'`'*) return 1 ;;
    *) printf '%s' "$value" ;;
  esac
}

path_has_dot_segments() {
  local remaining="${1#/}" segment
  while [[ -n "$remaining" ]]; do
    segment="${remaining%%/*}"
    [[ "$segment" == "." || "$segment" == ".." ]] && return 0
    [[ "$remaining" == */* ]] || break
    remaining="${remaining#*/}"
  done
  return 1
}

normalize_path() {
  local value="$1"
  while [[ "$value" == *//* ]]; do value="${value//\/\//\/}"; done
  while [[ "$value" != "/" && "$value" == */ ]]; do value="${value%/}"; done
  printf '%s' "$value"
}

path_contains_or_is() {
  local container="$1" candidate="$2"
  [[ "$candidate" == "$container" || "$candidate" == "$container/"* ]]
}

MANIFEST_PATHS=()
preflight_manifest() {
  local line source count=0 canonical=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    source="$(expand_manifest_path "$line")" || die "unsupported manifest expansion: $line"
    [[ "$source" == /* ]] || die "manifest paths must resolve to absolute paths: $line"
    [[ -n "${source//\//}" ]] || die "manifest paths must not use filesystem root: $line"
    path_has_dot_segments "$source" && die "manifest paths must not contain dot segments: $line"
    MANIFEST_PATHS+=("$source")
    [[ "${source%/}" == "${SECRETS_DIR%/}" ]] && canonical=1
    count=$((count + 1))
  done < "$MANIFEST"
  (( count > 0 )) || die "manifest contains no backup paths: $MANIFEST"
  (( canonical == 1 )) || die "manifest must include the canonical secrets tree: $SECRETS_DIR"
}
preflight_manifest

DEST_DEFAULT=""
[[ -f "$DEST_CACHE" ]] && DEST_DEFAULT="$(<"$DEST_CACHE")"
if [[ -n "${DOTFILES_BACKUP_DEST:-}" ]]; then
  DEST="$DOTFILES_BACKUP_DEST"
elif [[ -n "$DEST_DEFAULT" ]]; then
  if [[ -t 0 ]]; then
    read -r -p "Vault destination folder [$DEST_DEFAULT]: " DEST || DEST=""
    DEST="${DEST:-$DEST_DEFAULT}"
  else
    DEST="$DEST_DEFAULT"
  fi
elif [[ -t 0 ]]; then
  read -r -p "Vault destination folder: " DEST
else
  die "vault destination is not configured; set DOTFILES_BACKUP_DEST or run interactively once"
fi
DEST="${DEST//\\/}"
DEST="${DEST%\"}"; DEST="${DEST#\"}"
DEST="${DEST%\'}"; DEST="${DEST#\'}"
DEST="${DEST/#\~/$HOME}"
[[ -d "$DEST" ]] || die "destination does not exist: $DEST"
[[ -w "$DEST" ]] || die "destination not writable: $DEST"
[[ "$DEST" == /* ]] || die "destination must be an absolute path: $DEST"
DEST="$(cd -- "$DEST" && pwd -P)"

validate_manifest_containment() {
  local source source_lexical source_real dest_real
  dest_real="$(cd "$DEST" && pwd -P)"
  for source in "${MANIFEST_PATHS[@]}"; do
    source_lexical="$(normalize_path "$source")"
    if path_contains_or_is "$source_lexical" "$DEST" || path_contains_or_is "$DEST" "$source_lexical"; then
      die "manifest source must not overlap the vault destination: $source"
    fi
    [[ -e "$source" || -L "$source" ]] || continue
    source_real="$(realpath "$source" 2>/dev/null || true)"
    [[ -n "$source_real" ]] || continue
    if path_contains_or_is "$source_real" "$dest_real" || path_contains_or_is "$dest_real" "$source_real"; then
      die "manifest source must not resolve inside the vault destination: $source"
    fi
  done
}
validate_manifest_containment

mkdir -p "$LOCAL_DIR"
LOCK_DIR="$LOCAL_DIR/secrets-backup.lock"
LOCK_HELD=0
release_lock() {
  [[ $LOCK_HELD -eq 1 ]] && rm -rf -- "$LOCK_DIR"
  LOCK_HELD=0
}
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  lock_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  if [[ "$lock_pid" =~ ^[0-9]+$ ]] && kill -0 "$lock_pid" 2>/dev/null; then
    die "another secrets backup is already running (pid $lock_pid)"
  fi
  die "stale or invalid secrets-backup lock: $LOCK_DIR
  verify no backup is starting, remove that directory manually, and retry"
fi
printf '%s\n' "$$" > "$LOCK_DIR/pid"
LOCK_HELD=1
trap release_lock EXIT
printf '%s\n' "$DEST" > "$DEST_CACHE"

get_pass() {
  local password
  password="$(security find-generic-password -s "$KC_SERVICE" -a "$USER" -w 2>/dev/null)" || return 1
  [[ -n "$password" ]] || return 1
  printf '%s' "$password"
}

if ! get_pass >/dev/null; then
  existing_artifact="$(find "$DEST" -maxdepth 1 -type f \
    \( -name "${ARTIFACT_PREFIX}????????-??????.dmg" -o -name "$LEGACY_NAME" \) -print -quit)"
  [[ -z "$existing_artifact" ]] || die "existing vault found but its local Keychain password is missing
  recover the password from your independent password manager, then run:
  make secrets-pass-import"
  info "first run: generating vault passphrase → local login Keychain"
  PASS="$(openssl rand -base64 32)"
  security add-generic-password \
    -a "$USER" -s "$KC_SERVICE" \
    -D "disk image password" \
    -l "Dotfiles Secrets Vault" \
    -U -w "$PASS"
  unset PASS
  ok "passphrase saved locally as '$KC_SERVICE'"
fi

passphrase_fingerprint() {
  get_pass | shasum -a 256 | awk '{print $1}'
}

confirm_recovery_copy() {
  local reply fingerprint recorded=""
  fingerprint="$(passphrase_fingerprint)" || die "could not fingerprint the local vault password"
  [[ -n "$fingerprint" ]] || die "could not fingerprint the local vault password"
  if [[ -f "$RECOVERY_ACK" ]]; then
    recorded="$(awk -F= '$1 == "passphrase_sha256" { print $2; exit }' "$RECOVERY_ACK")"
    [[ -n "$recorded" && "$recorded" == "$fingerprint" ]] && return 0
    warn "recovery confirmation does not match the current Keychain password; reconfirming"
  fi
  warn "the login-Keychain item is local and is not guaranteed to sync through iCloud Keychain"
  warn "copy it with 'make secrets-pass', store it in an independently synchronized password manager,"
  warn "and verify that recovery copy from another device before continuing"
  if [[ "${DOTFILES_VAULT_RECOVERY_CONFIRMED:-}" == "1" ]]; then
    reply="y"
  elif [[ -t 0 ]]; then
    read -r -p "Recovery copy stored and verified? [y/N]: " reply
  else
    die "vault recovery copy is not confirmed
  after storing it safely, rerun interactively or set DOTFILES_VAULT_RECOVERY_CONFIRMED=1 once"
  fi
  [[ "$reply" =~ ^[Yy]$ ]] || die "vault creation/backup stopped until recovery is independently stored"
  {
    printf 'confirmed=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
    printf 'passphrase_sha256=%s\n' "$fingerprint"
  } > "$RECOVERY_ACK"
  chmod 600 "$RECOVERY_ACK"
  ok "external recovery confirmation recorded at $RECOVERY_ACK (no secret stored there)"
}
confirm_recovery_copy

WORK="$(mktemp -d "${TMPDIR:-/private/tmp}/dotfiles-secrets-portable.XXXXXX")"
# hdiutil reports physical mount paths (/private/var rather than /var).
WORK="$(cd "$WORK" && pwd -P)"
SOURCE_STAGE="$WORK/source"
SNAPSHOT="$SOURCE_STAGE/$STAMP"
LOCAL_IMAGE="$WORK/${ARTIFACT_PREFIX}${STAMP}.dmg"
VERIFY_MOUNT="$WORK/verify-mount"
ATTACH_PLIST="$WORK/attach.plist"
VERIFY_DEVICE=""
VERIFY_CLEANUP_DEVICE=""
PUBLISH_PARTIAL=""
META_PARTIAL=""
CHECKSUM_PARTIAL=""
FINAL_IMAGE="$DEST/${ARTIFACT_PREFIX}${STAMP}.dmg"
FINAL_META="${FINAL_IMAGE%.dmg}.json"
FINAL_CHECKSUM="${FINAL_IMAGE%.dmg}.sha256"
PUBLICATION_STARTED=0
PUBLICATION_COMPLETE=0

cleanup() {
  local status=$?
  trap - EXIT HUP INT TERM
  if [[ -n "$VERIFY_DEVICE" ]]; then
    hdiutil detach "$VERIFY_DEVICE" >/dev/null 2>&1 || true
  elif [[ -n "$VERIFY_CLEANUP_DEVICE" ]]; then
    hdiutil detach "$VERIFY_CLEANUP_DEVICE" >/dev/null 2>&1 || true
  fi
  [[ -n "$PUBLISH_PARTIAL" ]] && rm -f -- "$PUBLISH_PARTIAL"
  [[ -n "$META_PARTIAL" ]] && rm -f -- "$META_PARTIAL"
  [[ -n "$CHECKSUM_PARTIAL" ]] && rm -f -- "$CHECKSUM_PARTIAL"
  if (( PUBLICATION_STARTED && ! PUBLICATION_COMPLETE )); then
    rm -f -- "$FINAL_IMAGE" "$FINAL_META" "$FINAL_CHECKSUM"
  fi
  rm -rf -- "$WORK"
  release_lock
  exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$SNAPSHOT"
info "staging manifest → $STAMP"
COUNT=0
for source in "${MANIFEST_PATHS[@]}"; do
  if [[ ! -e "$source" && ! -L "$source" ]]; then
    warn "skip (missing): $source"
    continue
  fi
  if [[ "${source%/}" == "${SECRETS_DIR%/}" ]]; then
    destination="$SNAPSHOT/payload/secrets"
    mkdir -p "$destination"
    source_path="${source%/}/"
  else
    destination="$SNAPSHOT${source%/*}"
    mkdir -p "$destination"
    source_path="$source"
  fi
  # Archive mode includes devices and special files. Realm FIFOs can block
  # hdiutil's copy-helper indefinitely; back up data, not IPC endpoints.
  rsync -aL --no-devices --no-specials --quiet \
    --exclude='.DS_Store' --exclude='*.sock' --exclude='sockets' \
    --exclude='node_modules' --exclude='__pycache__' --exclude='*.pyc' \
    --exclude='com.microsoft.appcenter' \
    "$source_path" "$destination/" || die "rsync failed copying $source"
  COUNT=$((COUNT + 1))
done
(( COUNT > 0 )) || die "manifest produced 0 snapshot paths"
[[ -d "$SNAPSHOT/payload/secrets" ]] || die "canonical secrets payload was not staged"
printf 'schema=1\nsnapshot=%s\ncontainer=UDZO\nfilesystem=APFS\n' "$STAMP" > "$SNAPSHOT/.dotfiles-vault-format"

# Fail closed if staging ever admits a FIFO, socket, or device node.
special_entry="$(find "$SOURCE_STAGE" ! -type f ! -type d ! -type l -print -quit)" \
  || die "could not validate staged file types"
[[ -z "$special_entry" ]] || die "staging contains a special file; refusing image creation"

info "creating immutable encrypted APFS/UDZO image"
get_pass | hdiutil create \
  -srcfolder "$SOURCE_STAGE" \
  -format UDZO \
  -layout GPTSPUD \
  -fs APFS \
  -volname "$VOLNAME" \
  -encryption AES-256 \
  -stdinpass \
  "$LOCAL_IMAGE" >/dev/null

format="$(get_pass | hdiutil imageinfo -stdinpass -format "$LOCAL_IMAGE")"
[[ "$format" == "UDZO" ]] || die "unexpected image format: $format"
get_pass | hdiutil verify -stdinpass -quiet "$LOCAL_IMAGE" >/dev/null || die "local image verification failed"

mkdir -p "$VERIFY_MOUNT"
info "read-validating the completed image"
get_pass | hdiutil attach "$LOCAL_IMAGE" \
  -readonly -nobrowse -stdinpass -mountpoint "$VERIFY_MOUNT" -plist > "$ATTACH_PLIST"

entity_index=0
while :; do
  entity_device="$(/usr/bin/plutil -extract "system-entities.$entity_index.dev-entry" raw -o - "$ATTACH_PLIST" 2>/dev/null || true)"
  entity_mount="$(/usr/bin/plutil -extract "system-entities.$entity_index.mount-point" raw -o - "$ATTACH_PLIST" 2>/dev/null || true)"
  [[ -n "$entity_device" || -n "$entity_mount" ]] || break
  if [[ -z "$VERIFY_CLEANUP_DEVICE" && "$entity_device" == /dev/disk* ]]; then
    VERIFY_CLEANUP_DEVICE="$entity_device"
  fi
  if [[ "$entity_mount" == "$VERIFY_MOUNT" && "$entity_device" == /dev/disk* ]]; then
    VERIFY_DEVICE="$entity_device"
    break
  fi
  entity_index=$((entity_index + 1))
done
[[ -n "$VERIFY_DEVICE" ]] || die "completed image returned no verified mounted device"
mount | grep -F " on $VERIFY_MOUNT (apfs," >/dev/null || die "completed image did not mount as APFS"
DOTFILES_RESTORE_SOURCE="$VERIFY_MOUNT" bash "$SCRIPT_DIR/secrets-restore.sh" --check "$STAMP"
hdiutil detach "$VERIFY_DEVICE" >/dev/null
VERIFY_DEVICE=""
VERIFY_CLEANUP_DEVICE=""

IMAGE_SHA256="$(shasum -a 256 "$LOCAL_IMAGE" | awk '{print $1}')"
IMAGE_SIZE="$(stat -f '%z' "$LOCAL_IMAGE")"
CREATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
CREATED_MACOS="$(sw_vers -productVersion)"
LOCAL_META="$WORK/${ARTIFACT_PREFIX}${STAMP}.json"
cat > "$LOCAL_META" <<EOF
{
  "schema": 1,
  "snapshot": "$STAMP",
  "createdAt": "$CREATED_AT",
  "createdOnMacOS": "$CREATED_MACOS",
  "minimumMacOS": "13.0",
  "container": "UDZO",
  "partitionMap": "GPT",
  "filesystem": "APFS",
  "encryption": "AES-256",
  "filename": "$(basename "$FINAL_IMAGE")",
  "sizeBytes": $IMAGE_SIZE,
  "sha256": "$IMAGE_SHA256"
}
EOF

for target in "$FINAL_IMAGE" "$FINAL_META" "$FINAL_CHECKSUM"; do
  [[ ! -e "$target" ]] || die "refusing to overwrite existing artifact: $target"
done
PUBLISH_PARTIAL="$DEST/.${ARTIFACT_PREFIX}${STAMP}.dmg.partial"
META_PARTIAL="$DEST/.${ARTIFACT_PREFIX}${STAMP}.json.partial"
CHECKSUM_PARTIAL="$DEST/.${ARTIFACT_PREFIX}${STAMP}.sha256.partial"
for target in "$PUBLISH_PARTIAL" "$META_PARTIAL" "$CHECKSUM_PARTIAL"; do
  [[ ! -e "$target" ]] || die "stale publication partial exists: $target"
done

info "publishing immutable recovery artifact"
cp "$LOCAL_IMAGE" "$PUBLISH_PARTIAL"
chmod 600 "$PUBLISH_PARTIAL"
PUBLISHED_SHA256="$(shasum -a 256 "$PUBLISH_PARTIAL" | awk '{print $1}')"
[[ "$PUBLISHED_SHA256" == "$IMAGE_SHA256" ]] || die "published image checksum differs from local image"
PUBLICATION_STARTED=1
mv "$PUBLISH_PARTIAL" "$FINAL_IMAGE"
PUBLISH_PARTIAL=""
cp "$LOCAL_META" "$META_PARTIAL"
chmod 600 "$META_PARTIAL"
mv "$META_PARTIAL" "$FINAL_META"
META_PARTIAL=""
printf '%s  %s\n' "$IMAGE_SHA256" "$(basename "$FINAL_IMAGE")" > "$CHECKSUM_PARTIAL"
chmod 600 "$CHECKSUM_PARTIAL"
mv "$CHECKSUM_PARTIAL" "$FINAL_CHECKSUM"
CHECKSUM_PARTIAL=""
PUBLICATION_COMPLETE=1
ok "published $(basename "$FINAL_IMAGE") with checksum + metadata"

info "retention: keep newest $KEEP completed portable artifact(s)"
# Capture the scan before pruning: process substitution hides scan failures.
retention_images="$(
  find "$DEST" -maxdepth 1 -type f -name "${ARTIFACT_PREFIX}????????-??????.dmg" -print \
    | LC_ALL=C sort -r
)" || die "backup published, but retention scan failed; existing backups preserved"
completed_count=0
while IFS= read -r old_image; do
  [[ -n "$old_image" ]] || continue
  old_base="${old_image%.dmg}"
  [[ -f "$old_base.json" && -f "$old_base.sha256" ]] || continue
  completed_count=$((completed_count + 1))
  (( completed_count > KEEP )) || continue
  rm -f -- "$old_image" "$old_base.json" "$old_base.sha256"
  ok "pruned $(basename "$old_image")"
done <<< "$retention_images"

info "done — portable vault at $FINAL_IMAGE"
if [[ -e "$DEST/$LEGACY_NAME" ]]; then
  warn "legacy sparseimage preserved unchanged at $DEST/$LEGACY_NAME"
fi
