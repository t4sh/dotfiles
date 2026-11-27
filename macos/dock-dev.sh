#!/usr/bin/env bash
# Rebuild just the Dock tiles from the most recently backed-up layout.
set -euo pipefail
exec bash "$(dirname "${BASH_SOURCE[0]}")/dock.sh" --layout-only
