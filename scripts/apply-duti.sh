#!/usr/bin/env bash
# Apply duti settings and fail if duti prints per-mapping failures.
set -euo pipefail

SETTINGS="${1:-$HOME/.duti}"

if ! command -v duti >/dev/null 2>&1; then
  echo "duti is not installed; run: make brew" >&2
  exit 1
fi
if [ ! -f "$SETTINGS" ]; then
  echo "$SETTINGS missing; run: make link" >&2
  exit 1
fi

set +e
output="$(duti "$SETTINGS" 2>&1)"
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

echo "  ✓ default app mappings applied"
