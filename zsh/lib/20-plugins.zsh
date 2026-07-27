# Homebrew zsh plugins
# Install: brew install zsh-autosuggestions zsh-syntax-highlighting
# (zsh-autocomplete is disabled; see https://formulae.brew.sh/formula/zsh-autocomplete)

HOMEBREW_SHARE="${HOMEBREW_PREFIX:-/opt/homebrew}/share"

[[ -f "$HOMEBREW_SHARE/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] && \
  source "$HOMEBREW_SHARE/zsh-autosuggestions/zsh-autosuggestions.zsh"

export ZSH_HIGHLIGHT_HIGHLIGHTERS_DIR="$HOMEBREW_SHARE/zsh-syntax-highlighting/highlighters"
[[ -f "$HOMEBREW_SHARE/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] && \
  source "$HOMEBREW_SHARE/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

unset HOMEBREW_SHARE

# Override syntax-highlighting defaults
ZSH_HIGHLIGHT_STYLES[path]=
ZSH_HIGHLIGHT_STYLES[path_pathseparator]=fg=black,bold
ZSH_HIGHLIGHT_STYLES[path_prefix]=
