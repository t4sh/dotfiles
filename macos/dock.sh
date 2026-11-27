#!/usr/bin/env bash
# Windows uses native entry points; reject before any Unix-path mutation.
case "${OS:-}:$(uname -s)" in
  Windows_NT:*|*:MINGW*|*:MSYS*) echo 'This is a macOS workflow. On Windows run bin/dot.cmd help.' >&2; exit 2 ;;
esac
# Restore the Dock layout from macos/dock-backup.plist (captured by `make
# backup`). The snapshot owns layout and carries a full-domain copy of Dock
# policy because `defaults import` replaces the domain; defaults.sh remains the
# policy authority, and regression tests require overlapping values to agree.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
case "${1:-}" in
    '') PLIST="$DOTFILES/macos/dock-backup.plist" ;;
    --layout-only) PLIST="$DOTFILES/macos/dock-layout.plist" ;;
    *) echo "usage: dock.sh [--layout-only]" >&2; exit 2 ;;
esac

if [ ! -f "$PLIST" ]; then
    echo "  ⚠ $PLIST not found."
    if [[ -z "${1:-}" && -f "$DOTFILES/macos/dock-layout.plist" ]]; then
        echo "    Use bash macos/dock-dev.sh to restore the saved tile layout."
    fi
    exit 1
fi

materialized="$(mktemp -t dotfiles-dock.XXXXXX)"
trap 'rm -f "$materialized"' EXIT
python3 - "$PLIST" "$materialized" "${1:-}" <<'PY'
from pathlib import Path
import plistlib
import sys
import subprocess
from urllib.parse import quote
data = plistlib.loads(Path(sys.argv[1]).read_bytes())
for tile in data.get("persistent-apps", []):
    file_data = tile.get("tile-data", {}).get("file-data", {})
    url = file_data.get("_CFURLString", "")
    if url.startswith("file://__HOME__/"):
        file_data["_CFURLString"] = "file://" + quote(str(Path.home()) + url[len("file://__HOME__"):], safe="/")
if sys.argv[3] == "--layout-only":
    tiles = [plistlib.dumps(tile).decode("utf-8") for tile in data["persistent-apps"]]
    subprocess.run(["defaults", "write", "com.apple.dock", "persistent-apps", "-array", *tiles], check=True)
    subprocess.run(["defaults", "write", "com.apple.dock", "persistent-others", "-array"], check=True)
else:
    Path(sys.argv[2]).write_bytes(plistlib.dumps(data))
PY
if [[ -z "${1:-}" ]]; then
    defaults import com.apple.dock "$materialized"
fi
killall Dock
echo "  ✓ Dock layout restored from ${PLIST##*/}"
