# Source highlighting after plugins and 99-local.zsh so their editor widgets exist.
HOMEBREW_SHARE="${HOMEBREW_PREFIX:-/opt/homebrew}/share"

export ZSH_HIGHLIGHT_HIGHLIGHTERS_DIR="$HOMEBREW_SHARE/zsh-syntax-highlighting/highlighters"
if [[ -f "$HOMEBREW_SHARE/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
  source "$HOMEBREW_SHARE/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

  # Override syntax-highlighting defaults.
  ZSH_HIGHLIGHT_STYLES[path]=
  ZSH_HIGHLIGHT_STYLES[path_pathseparator]=fg=black,bold
  ZSH_HIGHLIGHT_STYLES[path_prefix]=
fi

unset HOMEBREW_SHARE
