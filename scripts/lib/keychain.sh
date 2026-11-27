#!/usr/bin/env bash
# Source only. Resolve one keychain://service reference for the current account.
# Call through command substitution; never print the returned value to a log.
dotfiles_resolve_secret() {
  case "$1" in
    keychain://*)
      local service="${1#keychain://}" secret
      [[ -n "$service" ]] || return 1
      if ! secret="$(/usr/bin/security find-generic-password -s "$service" -a "$(id -un)" -w 2>/dev/null)"; then
        return 1
      fi
      [[ -n "$secret" ]] || return 1
      printf '%s' "$secret"
      ;;
    *) printf '%s' "$1" ;; # Existing portable file-backed installations.
  esac
}
