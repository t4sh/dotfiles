#!/usr/bin/env bash
# Encrypted-sparseimage snapshot backup, Keychain-backed, destination-prompted.
#
# First run: prompts for vault destination (cached for subsequent runs),
#            generates a random passphrase to the login Keychain, creates
#            an AES-256 sparseimage at <destination>/DotfilesSecrets.sparseimage,
#            and snapshots the manifest into a dated subfolder.
# Later runs: reuse cached destination + Keychain passphrase (silent).
#
# To browse/extract: double-click the .sparseimage in Finder. Passphrase lives
# in Keychain Access → "Dotfiles Secrets Vault".
#
# Inputs (resolved at runtime, never committed):
#   Manifest     $DOTFILES_BACKUP_MANIFEST or ~/.dotfiles-local/backup.manifest
#   Destination  $DOTFILES_BACKUP_DEST or prompt (cached in ~/.dotfiles-local/backup.destination)
# Vault:       <destination>/DotfilesSecrets.sparseimage
# Snapshots:   /Volumes/DotfilesSecrets/YYYYMMDD-HHMMSS/<absolute-path-mirror>/
# Retention:   $DOTFILES_BACKUP_KEEP (default 10) newest dated folders.

set -euo pipefail

VOLNAME="DotfilesSecrets"
MOUNT="/Volumes/$VOLNAME"
KC_SERVICE="DotfilesSecretsVault"
LOCAL_DIR="${DOTFILES_LOCAL_DIR:-$HOME/.dotfiles-local}"
MANIFEST="${DOTFILES_BACKUP_MANIFEST:-$LOCAL_DIR/backup.manifest}"
DEST_CACHE="$LOCAL_DIR/backup.destination"
RECOVERY_ACK="$LOCAL_DIR/vault-recovery.confirmed"
KEEP="${DOTFILES_BACKUP_KEEP:-10}"
SIZE_CAP="${DOTFILES_VAULT_SIZE:-4g}"
STAMP="$(date +%Y%m%d-%H%M%S)"

[[ "$KEEP" =~ ^[1-9][0-9]*$ ]] || {
  printf '\033[31merror:\033[0m DOTFILES_BACKUP_KEEP must be a positive integer (got: %s)\n' "$KEEP" >&2
  exit 1
}

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  ⚠\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[[ -f "$MANIFEST" ]] || die "manifest not found: $MANIFEST
  create it at $MANIFEST (or set \$DOTFILES_BACKUP_MANIFEST)
  see scripts/backup-manifest.example for the format"

expand_manifest_path() {
  local s="$1"
  local secrets_dir="${DOTFILES_SECRETS_DIR:-$HOME/.secrets}"

  # Literal tilde/variable patterns are expanded manually below.
  # shellcheck disable=SC2088,SC2016
  case "$s" in
    '~') printf '%s' "$HOME" ;;
    '~/'*) printf '%s/%s' "$HOME" "${s#\~/}" ;;
    '$HOME') printf '%s' "$HOME" ;;
    '$HOME/'*) printf '%s/%s' "$HOME" "${s#\$HOME/}" ;;
    '${HOME}') printf '%s' "$HOME" ;;
    '${HOME}/'*) printf '%s/%s' "$HOME" "${s#\$\{HOME\}/}" ;;
    '$DOTFILES_SECRETS_DIR') printf '%s' "$secrets_dir" ;;
    '$DOTFILES_SECRETS_DIR/'*) printf '%s/%s' "$secrets_dir" "${s#\$DOTFILES_SECRETS_DIR/}" ;;
    '${DOTFILES_SECRETS_DIR}') printf '%s' "$secrets_dir" ;;
    '${DOTFILES_SECRETS_DIR}/'*) printf '%s/%s' "$secrets_dir" "${s#\$\{DOTFILES_SECRETS_DIR\}/}" ;;
    '$DOTFILES_LOCAL_DIR') printf '%s' "$LOCAL_DIR" ;;
    '$DOTFILES_LOCAL_DIR/'*) printf '%s/%s' "$LOCAL_DIR" "${s#\$DOTFILES_LOCAL_DIR/}" ;;
    '${DOTFILES_LOCAL_DIR}') printf '%s' "$LOCAL_DIR" ;;
    '${DOTFILES_LOCAL_DIR}/'*) printf '%s/%s' "$LOCAL_DIR" "${s#\$\{DOTFILES_LOCAL_DIR\}/}" ;;
    *'$'* | *'`'*) return 1 ;;
    *) printf '%s' "$s" ;;
  esac
}

MANIFEST_PATHS=()
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

preflight_manifest() {
  local line src count=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    src="$(expand_manifest_path "$line")" || die "unsupported manifest expansion: $line"
    [[ "$src" == /* ]] || die "manifest paths must resolve to absolute paths: $line"
    path_has_dot_segments "$src" && die "manifest paths must not contain dot segments: $line"
    MANIFEST_PATHS+=("$src")
    count=$((count + 1))
  done < "$MANIFEST"
  (( count > 0 )) || die "manifest contains no backup paths: $MANIFEST"
}

# Reject invalid or relative paths before selecting a destination, taking the
# lock, mounting a vault, pruning snapshots, or making any other mutation.
preflight_manifest

# --- destination: env var → cache default → prompt ---
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

# Sanitize Finder-pasted paths (strip escapes + surrounding quotes, expand ~)
DEST="${DEST//\\/}"
DEST="${DEST%\"}"; DEST="${DEST#\"}"
DEST="${DEST%\'}"; DEST="${DEST#\'}"
DEST="${DEST/#\~/$HOME}"

[[ -d "$DEST" ]] || die "destination does not exist: $DEST"
[[ -w "$DEST" ]] || die "destination not writable: $DEST"

VAULT="$DEST/DotfilesSecrets.sparseimage"

path_contains_or_is() {
  local container="$1" candidate="$2"
  [[ "$candidate" == "$container" || "$candidate" == "$container/"* ]]
}

normalize_lexical_absolute_path() {
  local path="$1"
  while [[ "$path" == *//* ]]; do
    path="${path//\/\//\/}"
  done
  while [[ "$path" != "/" && "$path" == */ ]]; do
    path="${path%/}"
  done
  printf '%s' "$path"
}

validate_manifest_containment() {
  local src src_lexical src_real mount_lexical mount_real vault_lexical vault_real
  mount_lexical="$(normalize_lexical_absolute_path "$MOUNT")"
  vault_lexical="$(normalize_lexical_absolute_path "$VAULT")"
  mount_real="$(cd "$(dirname "$MOUNT")" && pwd -P)/$(basename "$MOUNT")"
  vault_real="$(cd "$(dirname "$VAULT")" && pwd -P)/$(basename "$VAULT")"
  for src in "${MANIFEST_PATHS[@]}"; do
    # Lexical containment must run even when a first-run source does not exist
    # yet. The selected image and mount are created later in this process.
    src_lexical="$(normalize_lexical_absolute_path "$src")"
    if path_contains_or_is "$mount_lexical" "$src_lexical" || \
       path_contains_or_is "$src_lexical" "$mount_lexical"; then
      die "manifest source must not overlap the vault mount: $src"
    fi
    if path_contains_or_is "$src_lexical" "$vault_lexical" || \
       path_contains_or_is "$vault_lexical" "$src_lexical"; then
      die "manifest source must not contain or resolve to the vault image: $src"
    fi

    # Existing symlinks can hide overlap that is not visible lexically.
    [[ -e "$src" || -L "$src" ]] || continue
    src_real="$(realpath "$src" 2>/dev/null || true)"
    [[ -n "$src_real" ]] || continue
    if path_contains_or_is "$mount_real" "$src_real" || \
       path_contains_or_is "$src_real" "$mount_real"; then
      die "manifest source must not overlap the vault mount: $src"
    fi
    if path_contains_or_is "$src_real" "$vault_real" || \
       path_contains_or_is "$vault_real" "$src_real"; then
      die "manifest source must not contain or resolve to the vault image: $src"
    fi
  done
}

# Destination-aware safety still runs before lock/cache creation, mounting, or
# retention pruning. `rsync -L` follows links, so compare resolved source paths.
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
  if [[ "$lock_pid" =~ ^[0-9]+$ ]]; then
    if kill -0 "$lock_pid" 2>/dev/null; then
      die "another secrets backup is already running (pid $lock_pid)"
    fi
    die "stale secrets-backup lock belongs to exited pid $lock_pid: $LOCK_DIR
  verify no backup is starting, remove that stale directory manually, and retry"
  else
    die "backup lock exists without a valid pid: $LOCK_DIR
  if no backup is starting, remove that stale directory and retry"
  fi
fi
printf '%s\n' "$$" > "$LOCK_DIR/pid"
LOCK_HELD=1
trap release_lock EXIT

# Persist the selected destination only after this process owns the backup lock;
# a rejected concurrent invocation must not redirect future backup/mount runs.
printf '%s\n' "$DEST" > "$DEST_CACHE"

# --- passphrase: create once in the local login Keychain ---
# `security add-generic-password` does not create a synchronizable Keychain
# item. Recovery therefore requires a separately stored copy in a trusted,
# independently synchronized password manager.
#
# `security -w` appends a trailing newline on stdout. `hdiutil -stdinpass`
# would treat that newline as part of the passphrase, while Finder's typed
# password has none — causing Finder "wrong password" errors on double-click.
# Use $() to strip the trailing newline and printf '%s' to emit raw bytes.
get_pass() {
  local p
  if ! p="$(security find-generic-password -s "$KC_SERVICE" -a "$USER" -w 2>/dev/null)"; then
    return 1
  fi
  [[ -n "$p" ]] || return 1
  printf '%s' "$p"
}

if ! get_pass >/dev/null; then
  if [[ -e "$VAULT" ]]; then
    die "existing vault found but its local Keychain password is missing: $VAULT
  recover the password from your independent password manager, then run:
  make secrets-pass-import"
  fi
  info "first run: generating vault passphrase → local login Keychain"
  # macOS `security add-generic-password` accepts the secret via `-w` only; keep
  # the exposure limited to this create-once command and immediately unset it.
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
  # The generated passphrase has 256 bits of entropy. Its SHA-256 fingerprint
  # is a non-secret equality check that invalidates acknowledgements after any
  # Keychain password change without storing the password itself.
  get_pass | shasum -a 256 | awk '{print $1}'
}

confirm_recovery_copy() {
  local reply fingerprint recorded=""
  if ! fingerprint="$(passphrase_fingerprint)" || [[ -z "$fingerprint" ]]; then
    die "could not fingerprint the local vault password"
  fi
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

# --- vault: create once ---
if [[ ! -e "$VAULT" ]]; then
  info "creating encrypted sparseimage at $VAULT ($SIZE_CAP cap, grows on demand)"
  get_pass | hdiutil create \
    -type SPARSE -encryption AES-256 -stdinpass \
    -volname "$VOLNAME" -fs APFS -size "$SIZE_CAP" \
    "$VAULT" >/dev/null
  ok "created $VAULT"
fi

# --- mount selected vault and verify its exact returned device identity ---
is_mounted() {
  mount | grep -F " on $MOUNT " >/dev/null 2>&1
}

MOUNTED_BY_US=0
ATTACHED_DEVICE=""
ATTACH_CLEANUP_DEVICE=""
ATTACH_PLIST=""
PARTIAL=""
cleanup() {
  local status=$?
  if [[ -n "$PARTIAL" && -d "$PARTIAL" ]]; then
    rm -rf -- "$PARTIAL" || true
  fi
  [[ -n "$ATTACH_PLIST" ]] && rm -f -- "$ATTACH_PLIST"
  if [[ $MOUNTED_BY_US -eq 1 ]]; then
    if [[ -n "$ATTACHED_DEVICE" ]]; then
      hdiutil detach "$ATTACHED_DEVICE" >/dev/null 2>&1 || true
    elif [[ -n "$ATTACH_CLEANUP_DEVICE" ]]; then
      hdiutil detach "$ATTACH_CLEANUP_DEVICE" >/dev/null 2>&1 || true
    elif is_mounted; then
      hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
    fi
  fi
  release_lock
  return "$status"
}
trap cleanup EXIT

# Resolve the selected image before calling attach. `hdiutil attach` reports an
# already-attached image as though this process attached it, so mountpoint-only
# detection can otherwise claim and detach an operator-owned device.
resolve_selected_vault_attachment() {
  local info_plist image_index entity_index image_path entity_mount entity_device
  local vault_real image_real first_device first_mount
  info_plist="$(mktemp "${TMPDIR:-/tmp}/dotfiles-vault-info.XXXXXX")"
  if ! hdiutil info -plist > "$info_plist" 2>/dev/null; then
    rm -f -- "$info_plist"
    return 2
  fi
  vault_real="$(cd "$(dirname "$VAULT")" && pwd -P)/$(basename "$VAULT")"
  image_index=0
  while :; do
    image_path="$(/usr/bin/plutil -extract "images.$image_index.image-path" raw -o - "$info_plist" 2>/dev/null || true)"
    [[ -n "$image_path" ]] || break
    if [[ -e "$image_path" ]]; then
      image_real="$(cd "$(dirname "$image_path")" && pwd -P)/$(basename "$image_path")"
    else
      image_real="$image_path"
    fi
    if [[ "$image_real" == "$vault_real" ]]; then
      first_device=""
      first_mount=""
      entity_index=0
      while :; do
        entity_device="$(/usr/bin/plutil -extract "images.$image_index.system-entities.$entity_index.dev-entry" raw -o - "$info_plist" 2>/dev/null || true)"
        entity_mount="$(/usr/bin/plutil -extract "images.$image_index.system-entities.$entity_index.mount-point" raw -o - "$info_plist" 2>/dev/null || true)"
        [[ -n "$entity_device" || -n "$entity_mount" ]] || break
        if [[ "$entity_mount" == "$MOUNT" && "$entity_device" == /dev/disk* ]]; then
          printf '%s\t%s' "$entity_device" "$entity_mount"
          rm -f -- "$info_plist"
          return 0
        fi
        if [[ -z "$first_device" && "$entity_device" == /dev/disk* ]]; then
          first_device="$entity_device"
          first_mount="$entity_mount"
        fi
        entity_index=$((entity_index + 1))
      done
      if [[ -n "$first_device" ]]; then
        printf '%s\t%s' "$first_device" "$first_mount"
        rm -f -- "$info_plist"
        return 0
      fi
      rm -f -- "$info_plist"
      return 2
    fi
    image_index=$((image_index + 1))
  done
  rm -f -- "$info_plist"
  return 1
}

WAS_MOUNTED=0
EXISTING_ATTACHMENT=""
attachment_status=0
EXISTING_ATTACHMENT="$(resolve_selected_vault_attachment)" || attachment_status=$?
case "$attachment_status" in
  0)
    existing_device="${EXISTING_ATTACHMENT%%$'\t'*}"
    existing_mount="${EXISTING_ATTACHMENT#*$'\t'}"
    if [[ "$existing_mount" == "$MOUNT" ]]; then
      if [[ ! -d "$MOUNT" ]] || ! is_mounted; then
        die "selected vault reports $MOUNT but it is not a live mounted volume; detach it manually and re-run"
      fi
      ATTACHED_DEVICE="$existing_device"
      WAS_MOUNTED=1
    else
      [[ -n "$existing_mount" ]] || existing_mount="an unmounted device"
      die "selected vault is already attached at $existing_mount ($existing_device)
  leave that operator-owned attachment in place, or detach it manually before re-running"
    fi
    ;;
  1) ;;
  *) die "could not determine whether the selected vault is already attached: $VAULT" ;;
esac

if [[ $WAS_MOUNTED -eq 0 && -d "$MOUNT" ]]; then
  is_mounted || die "$MOUNT exists but is not a mounted volume; remove the stale directory and re-run"
  die "$MOUNT is mounted but is not the selected vault: $VAULT
  unmount it (eject in Finder or: hdiutil detach \"$MOUNT\") and re-run"
fi

if [[ $WAS_MOUNTED -eq 1 ]]; then
  info "vault already mounted at $MOUNT — selected image identity verified"
  ok "using already-mounted vault ($ATTACHED_DEVICE)"
  MOUNTED_BY_US=0
else
  info "attaching selected vault"
  ATTACH_PLIST="$(mktemp "${TMPDIR:-/tmp}/dotfiles-vault-attach.XXXXXX")"
  if ! get_pass | hdiutil attach "$VAULT" -stdinpass -mountpoint "$MOUNT" -nobrowse -plist > "$ATTACH_PLIST"; then
    die "could not attach selected vault: $VAULT"
  fi
  # Own the mount for EXIT cleanup immediately — plist parse can still fail.
  MOUNTED_BY_US=1

  # hdiutil's attach plist links the selected sparseimage to its /dev/disk node
  # and mount point. A directory/mount name alone is not sufficient proof.
  entity_index=0
  while :; do
    entity_device="$(/usr/bin/plutil -extract "system-entities.$entity_index.dev-entry" raw -o - "$ATTACH_PLIST" 2>/dev/null || true)"
    entity_mount="$(/usr/bin/plutil -extract "system-entities.$entity_index.mount-point" raw -o - "$ATTACH_PLIST" 2>/dev/null || true)"
    [[ -n "$entity_device" || -n "$entity_mount" ]] || break
    if [[ -z "$ATTACH_CLEANUP_DEVICE" && "$entity_device" == /dev/disk* ]]; then
      ATTACH_CLEANUP_DEVICE="$entity_device"
    fi
    if [[ "$entity_mount" == "$MOUNT" && "$entity_device" == /dev/disk* ]]; then
      ATTACHED_DEVICE="$entity_device"
      ATTACH_CLEANUP_DEVICE="$entity_device"
      break
    fi
    entity_index=$((entity_index + 1))
  done
  [[ -n "$ATTACHED_DEVICE" ]] || die "selected vault did not attach as $MOUNT with a verified /dev/disk identity"
  rm -f -- "$ATTACH_PLIST"
  ATTACH_PLIST=""
fi
[[ -d "$MOUNT" && -w "$MOUNT" ]] || die "vault mount is not writable: $MOUNT"

prune_snapshots() {
  local target_keep="$1"
  info "retention: keep newest $target_keep finalized snapshot(s)"
  /usr/bin/find "$MOUNT" -maxdepth 1 -type d \
    -name '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]' \
    | sort -r | tail -n +"$((target_keep + 1))" \
    | while IFS= read -r d; do
        [[ -z "$d" ]] && continue
        rm -rf -- "$d"
        ok "pruned $(basename "$d")"
      done
}

estimate_manifest_kb() {
  local total=0 src kb
  for src in "${MANIFEST_PATHS[@]}"; do
    if [[ ! -e "$src" && ! -L "$src" ]]; then
      continue
    fi
    # The snapshot uses rsync -L, so estimate the dereferenced target too.
    if ! kb="$(du -skL "$src" 2>/dev/null | awk '{print $1}')"; then
      warn "could not measure manifest path: $src" >&2
      return 1
    fi
    [[ -n "$kb" ]] || {
      warn "empty size result for manifest path: $src" >&2
      return 1
    }
    total=$((total + kb))
  done
  printf '%s' "$total"
}

check_vault_space() {
  local needed_kb avail_kb needed_mb avail_mb
  needed_kb="$(estimate_manifest_kb)"
  avail_kb="$(df -k "$MOUNT" | awk 'NR==2 {print $4}')"
  needed_mb=$(( (needed_kb + 1023) / 1024 ))
  avail_mb=$(( avail_kb / 1024 ))
  # ~10% headroom for APFS metadata and concurrent writes
  if (( needed_kb * 11 / 10 > avail_kb )); then
    die "vault low on space: manifest needs ~${needed_mb}Mi free, mount has ~${avail_mb}Mi
  prune: lower retention and re-run, e.g. DOTFILES_BACKUP_KEEP=5 make secrets-backup
  grow:  hdiutil resize -size 8g \"$VAULT\"  (then re-run)"
  fi
}

# Enforce any explicitly lowered/exceeded retention before checking capacity,
# but never delete below KEEP merely to attempt a backup. A failed copy must
# preserve every snapshot within policy. Normal pruning happens after publish.
prune_snapshots "$KEEP"
check_vault_space

# --- snapshot into a hidden partial folder, then publish atomically ---
SNAP="$MOUNT/$STAMP"
PARTIAL="$MOUNT/.$STAMP.partial"
[[ ! -e "$SNAP" && ! -e "$PARTIAL" ]] || die "snapshot name collision for $STAMP — wait one second and retry"
mkdir -p "$PARTIAL"
info "snapshotting manifest → .$STAMP.partial"
COUNT=0
for src in "${MANIFEST_PATHS[@]}"; do
  if [[ ! -e "$src" && ! -L "$src" ]]; then
    warn "skip (missing): $src"
    continue
  fi
  dst_parent="$PARTIAL${src%/*}"
  mkdir -p "$dst_parent"
  if ! rsync -aL --quiet \
        --exclude='.DS_Store' --exclude='*.sock' --exclude='sockets' \
        --exclude='node_modules' --exclude='__pycache__' --exclude='*.pyc' \
        --exclude='com.microsoft.appcenter' \
        "$src" "$dst_parent/"; then
    die "rsync failed copying $src — partial snapshot will be removed
  if the vault was full, prune or resize before retrying (see check_vault_space hints above)"
  fi
  COUNT=$((COUNT + 1))
done
if (( COUNT == 0 )); then
  die "manifest produced 0 snapshot paths; partial snapshot will be removed"
fi
mv "$PARTIAL" "$SNAP"
PARTIAL=""
ok "published $STAMP with $COUNT path(s)"
prune_snapshots "$KEEP"

# --- unmount + compact so destination uploads stay small ---
if [[ $MOUNTED_BY_US -eq 1 ]]; then
  info "unmounting + compacting"
  hdiutil detach "$ATTACHED_DEVICE" >/dev/null
  MOUNTED_BY_US=0
  ATTACHED_DEVICE=""
  ATTACH_CLEANUP_DEVICE=""
  if ! get_pass | hdiutil compact "$VAULT" -stdinpass >/dev/null 2>&1; then
    die "snapshot succeeded, but vault compaction failed: $VAULT"
  fi
  ok "compacted"
fi

info "done — vault at $VAULT"
