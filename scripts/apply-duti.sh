#!/usr/bin/env bash
# Apply duti settings and fail if duti prints per-mapping failures.
# Missing app bundle IDs are skipped with warnings so optional handlers (for
# example full Xcode.app) can remain in config/duti without breaking fresh Macs.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
SETTINGS="${1:-$DOTFILES/config/duti}"
STATE_DIR="${DOTFILES_STATE_DIR:-$HOME/.dotfiles-local}"
STATE_FILE="$STATE_DIR/default-apps.sha256"

warn() { printf '  ⚠ %s\n' "$*" >&2; }

if ! command -v duti >/dev/null 2>&1; then
  echo "duti is not installed; run: make brew" >&2
  exit 1
fi
if [ ! -f "$SETTINGS" ]; then
  echo "$SETTINGS missing" >&2
  exit 1
fi

_bundle_exists_find() {
  local bundle_id="$1"
  /usr/bin/find /Applications /System/Applications "$HOME/Applications" \
    -maxdepth 3 -name '*.app' -prune -print 2>/dev/null \
    | while IFS= read -r app; do
        /usr/bin/defaults read "$app/Contents/Info" CFBundleIdentifier 2>/dev/null || true
      done \
    | grep -Fxq "$bundle_id"
}

_bundle_exists_lookup() {
  local bundle_id="$1"
  if command -v mdfind >/dev/null 2>&1; then
    if mdfind "kMDItemCFBundleIdentifier == '$bundle_id'" | grep -q .; then
      return 0
    fi
  fi
  # Fallback when Spotlight is unavailable or has not indexed the app yet.
  _bundle_exists_find "$bundle_id"
}

bundle_exists() {
  local bundle_id="$1"
  local cached

  cached="$(awk -F'\t' -v id="$bundle_id" '$1 == id { hit = $2 } END { print hit }' "$bundle_cache")"
  case "$cached" in
    1) return 0 ;;
    0) return 1 ;;
  esac

  if _bundle_exists_lookup "$bundle_id"; then
    printf '%s\t1\n' "$bundle_id" >> "$bundle_cache"
    return 0
  fi
  printf '%s\t0\n' "$bundle_id" >> "$bundle_cache"
  return 1
}

filtered="$(mktemp -t duti.apply.XXXXXX)"
bundle_cache="$(mktemp -t duti.bundle-cache.XXXXXX)"
trap 'rm -f "$filtered" "$bundle_cache"' EXIT

skipped=0
while IFS= read -r line || [ -n "$line" ]; do
  trimmed="${line#"${line%%[![:space:]]*}"}"
  case "${trimmed:-}" in
    ''|'#'*)
      printf '%s\n' "$line" >> "$filtered"
      continue
      ;;
  esac

  read -r bundle_id _rest <<< "$trimmed"
  if bundle_exists "$bundle_id"; then
    printf '%s\n' "$line" >> "$filtered"
  else
    warn "skipping missing app bundle: $bundle_id"
    skipped=$((skipped + 1))
  fi
done < "$SETTINGS"

applied=0
while read -r bundle_id target role; do
  case "${bundle_id:-}" in ''|'#'*) continue ;; esac
  set +e
  if [[ -n "${role:-}" ]]; then
    output="$(duti -s "$bundle_id" "$target" "$role" 2>&1)"
  else
    output="$(duti -s "$bundle_id" "$target" 2>&1)"
  fi
  status=$?
  set -e
  if [[ -n "$output" ]]; then printf '%s\n' "$output" >&2; fi
  if (( status != 0 )) || printf '%s\n' "$output" | grep -qi '^failed to set '; then
    echo "duti failed to apply: $bundle_id $target ${role:-}" >&2
    exit 1
  fi
  applied=$((applied + 1))
done < "$filtered"

if ! bash "$DOTFILES/scripts/check-duti.sh" "$filtered"; then
  echo "default-app policy did not converge; receipt not written" >&2
  exit 1
fi

if (( skipped > 0 )); then
  echo "  ✓ $applied default app mappings applied ($skipped missing bundle(s) skipped)"
else
  echo "  ✓ $applied default app mappings applied"
fi

mkdir -p "$STATE_DIR"
shasum -a 256 "$SETTINGS" | awk '{print $1}' > "$STATE_FILE"
chmod 600 "$STATE_FILE"
echo "  ✓ default-app policy receipt recorded"
