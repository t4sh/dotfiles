# PATH — deduplicated, loaded first

typeset -U PATH

export PATH="/usr/local/bin:$PATH"
export PATH="/usr/local/sbin:$PATH"
export PATH="/opt/homebrew/bin:$PATH"
export PATH="$PATH:$HOME/.local/bin"
export PATH="$HOME/.dotfiles/bin:$PATH"

# Non-login interactive shells skip .zprofile; initialize whichever standard
# Homebrew prefix is actually on PATH before later tool/plugin files load.
if [[ -z "${HOMEBREW_PREFIX:-}" ]] && command -v brew >/dev/null 2>&1; then
  eval "$(brew shellenv)"
fi
