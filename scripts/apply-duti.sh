#!/usr/bin/env bash
# Apply duti settings and fail if duti prints per-mapping failures.
# Missing app bundle IDs are skipped with warnings so optional handlers (for
# example full Xcode.app) can remain in config/duti without breaking fresh Macs.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
SETTINGS="${1:-$DOTFILES/config/duti}"

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

set +e
output="$(duti "$filtered" 2>&1)"
status=$?
set -e
if [ -n "$output" ]; then
  printf '%s\n' "$output" >&2
fi
if [ "$status" -ne 0 ]; then
  exit "$status"
fi
if printf '%s\n' "$output" | grep -qi '^failed to set '; then
  echo "duti reported one or more mapping failures" >&2
  exit 1
fi

if (( skipped > 0 )); then
  echo "  ✓ default app mappings applied ($skipped missing bundle(s) skipped)"
else
  echo "  ✓ default app mappings applied"
fi
