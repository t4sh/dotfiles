#!/usr/bin/env bash
set -euo pipefail

binary="$HOME/.local/bin/browse"
case "${1:-}" in
  install)
    if [[ ! -x "$binary" ]]; then
      installer="$(mktemp)"
      trap 'rm -f -- "$installer"' EXIT
      curl --fail --silent --show-error --location https://opencode.ai/browse/install --output "$installer"
      # The managed MCP config points here even when an interactive shell sets XDG_BIN_HOME.
      env -u OPENCODE_BROWSER_HOME XDG_BIN_HOME="$HOME/.local/bin" sh "$installer" --no-setup
    fi
    "$binary" version
    echo 'OpenCode Browse binary ready. For a new browser profile, install the Browse extension and run ~/.local/bin/browse pair.'
    ;;
  check)
    root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
    config="$HOME/.config/opencode/opencode.jsonc"
    if [[ ! -L "$config" || ! "$config" -ef "$root/config/opencode/macos.jsonc" ]]; then
      echo 'OpenCode config link has drifted. Run make link.' >&2
      exit 1
    fi
    if [[ ! -x "$binary" ]]; then
      echo 'Browse executable missing. Run make browse-install.' >&2
      exit 1
    fi
    # A new OpenCode service can list no servers while it loads its configuration.
    deadline=$((SECONDS + 15))
    while :; do
      listing="$(NO_COLOR=1 opencode mcp list)"
      if grep -Eq '^[[:space:]]*✓[[:space:]]+browse[[:space:]]+connected[[:space:]]*$' <<< "$listing"; then
        echo 'OpenCode Browse MCP connected.'
        exit 0
      fi
      if (( SECONDS >= deadline )) || grep -Eq '^[[:space:]]*✗[[:space:]]+browse[[:space:]]' <<< "$listing"; then
        echo 'OpenCode did not report Browse connected. Inspect opencode mcp list.' >&2
        exit 1
      fi
      sleep 1
    done
    ;;
  *) echo 'Usage: opencode-browse.sh install|check' >&2; exit 2 ;;
esac
