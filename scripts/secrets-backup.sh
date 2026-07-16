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

mkdir -p "$LOCAL_DIR"
printf '%s\n' "$DEST" > "$DEST_CACHE"

VAULT="$DEST/DotfilesSecrets.sparseimage"

# --- passphrase: create-once, Keychain-stored, iCloud-Keychain-synced ---
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
  info "first run: generating vault passphrase → login Keychain (syncs via iCloud Keychain)"
  # macOS `security add-generic-password` accepts the secret via `-w` only; keep
  # the exposure limited to this create-once command and immediately unset it.
  PASS="$(openssl rand -base64 32)"
  security add-generic-password \
    -a "$USER" -s "$KC_SERVICE" \
    -D "disk image password" \
    -l "Dotfiles Secrets Vault" \
    -U -w "$PASS"
  unset PASS
  ok "passphrase saved as '$KC_SERVICE' — you will never need to type it"
fi

# --- vault: create once ---
if [[ ! -e "$VAULT" ]]; then
  info "creating encrypted sparseimage at $VAULT ($SIZE_CAP cap, grows on demand)"
  get_pass | hdiutil create \
    -type SPARSE -encryption AES-256 -stdinpass \
    -volname "$VOLNAME" -fs APFS -size "$SIZE_CAP" \
    "$VAULT" >/dev/null
  ok "created $VAULT"
fi

# --- mount (idempotent) ---
is_mounted() {
  mount | grep -F " on $MOUNT " >/dev/null 2>&1
}

MOUNTED_BY_US=0
if [[ -d "$MOUNT" ]]; then
  is_mounted || die "$MOUNT exists but is not a mounted volume; remove the stale directory and re-run"
else
  info "mounting vault"
  get_pass | hdiutil attach "$VAULT" -stdinpass -mountpoint "$MOUNT" -nobrowse >/dev/null
  MOUNTED_BY_US=1
fi
[[ -d "$MOUNT" && -w "$MOUNT" ]] || die "vault mount is not writable: $MOUNT"

cleanup() {
  [[ $MOUNTED_BY_US -eq 1 ]] && hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
}
trap cleanup EXIT

prune_snapshots() {
  info "retention: keep newest $KEEP (override: DOTFILES_BACKUP_KEEP=<n> make secrets-backup)"
  /usr/bin/find "$MOUNT" -maxdepth 1 -type d \
    -name '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]' \
    | sort -r | tail -n +"$((KEEP + 1))" \
    | while IFS= read -r d; do
        [[ -z "$d" ]] && continue
        rm -rf "$d"
        ok "pruned $(basename "$d")"
      done
}

estimate_manifest_kb() {
  local total=0 line src kb
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    if ! src="$(expand_manifest_path "$line")"; then
      continue
    fi
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
  done < "$MANIFEST"
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

# --- prune first so a full snapshot always has room (prune-after left partials when full) ---
prune_snapshots
check_vault_space

# --- snapshot into dated folder, preserving absolute paths ---
SNAP="$MOUNT/$STAMP"
mkdir -p "$SNAP"
info "snapshotting manifest → $STAMP"
COUNT=0
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%%#*}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" ]] && continue
  if ! src="$(expand_manifest_path "$line")"; then
    warn "skip (unsupported expansion): $line"
    continue
  fi
  if [[ ! -e "$src" && ! -L "$src" ]]; then
    warn "skip (missing): $src"
    continue
  fi
  dst_parent="$SNAP${src%/*}"
  mkdir -p "$dst_parent"
  if ! rsync -aL --quiet \
        --exclude='.DS_Store' --exclude='*.sock' --exclude='sockets' \
        --exclude='node_modules' --exclude='__pycache__' --exclude='*.pyc' \
        --exclude='com.microsoft.appcenter' \
        "$src" "$dst_parent/"; then
    rm -rf "${SNAP:?}"
    die "rsync failed copying $src — removed partial snapshot $STAMP
  if the vault was full, prune or resize before retrying (see check_vault_space hints above)"
  fi
  COUNT=$((COUNT + 1))
done < "$MANIFEST"
if (( COUNT == 0 )); then
  rm -rf "${SNAP:?}"
  die "manifest produced 0 snapshot paths; removed empty snapshot $STAMP"
fi
ok "snapshotted $COUNT path(s)"

# --- unmount + compact so iCloud uploads stay small ---
if [[ $MOUNTED_BY_US -eq 1 ]]; then
  info "unmounting + compacting"
  hdiutil detach "$MOUNT" >/dev/null
  MOUNTED_BY_US=0
  get_pass | hdiutil compact "$VAULT" -stdinpass >/dev/null 2>&1 && ok "compacted"
fi

info "done — vault at $VAULT"
