# Homebrew autosuggestions; syntax highlighting loads in 99-syntax-highlighting.zsh.
# Install: brew install zsh-autosuggestions zsh-syntax-highlighting

HOMEBREW_SHARE="${HOMEBREW_PREFIX:-/opt/homebrew}/share"

[[ -f "$HOMEBREW_SHARE/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] && \
  source "$HOMEBREW_SHARE/zsh-autosuggestions/zsh-autosuggestions.zsh"

unset HOMEBREW_SHARE
