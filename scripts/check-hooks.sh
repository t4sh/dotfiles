#!/usr/bin/env bash
# Verify this checkout uses the tracked dotfiles hook directory.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
EXPECTED=".githooks"

actual="$(git -C "$DOTFILES" config --local --get core.hooksPath || true)"
if [[ "$actual" != "$EXPECTED" ]]; then
  echo "git core.hooksPath drifted: expected $EXPECTED, got ${actual:-<unset>}" >&2
  exit 1
fi

[[ -d "$DOTFILES/$EXPECTED" ]] || {
  echo "managed hook directory missing: $DOTFILES/$EXPECTED" >&2
  exit 1
}

found=0
while IFS= read -r -d '' hook; do
  found=$((found + 1))
  [[ -x "$hook" ]] || {
    echo "managed hook is not executable: $hook" >&2
    exit 1
  }
done < <(find "$DOTFILES/$EXPECTED" -maxdepth 1 -type f -print0)

(( found > 0 )) || {
  echo "managed hook directory contains no hooks: $DOTFILES/$EXPECTED" >&2
  exit 1
}

echo "Git hooks: core.hooksPath=$EXPECTED; $found executable hook(s)"
