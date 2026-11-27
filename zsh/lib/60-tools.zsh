# Tool initializers — lazy loaders and tool-specific PATH entries.

autoload -Uz add-zsh-hook

# NVM — lazy-load on first invocation for fast shell startup.
nvm() {
    unset -f nvm
    local nvm_sh="${HOMEBREW_PREFIX:-/opt/homebrew}/opt/nvm/nvm.sh"
    [ -s "$nvm_sh" ] && \. "$nvm_sh"
    nvm "$@"
}

# Dotfiles default node on PATH for fast startup. Per-repo .nvmrc still wins
# after auto_nvm_use runs.
DOTFILES_NODE_VERSION="$(cat "$HOME/.dotfiles/.node-version" 2>/dev/null)"
if [[ -n "$DOTFILES_NODE_VERSION" && -d "$NVM_DIR/versions/node/$DOTFILES_NODE_VERSION/bin" ]]; then
  export PATH="$NVM_DIR/versions/node/$DOTFILES_NODE_VERSION/bin:$PATH"
fi
unset DOTFILES_NODE_VERSION

# Chpwd hook for auto-nvm (auto_nvm_use is defined in 50-functions.zsh).
add-zsh-hook chpwd auto_nvm_use
auto_nvm_use

# pnpm
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

# fzf — fuzzy file/history selectors.
if [[ -o interactive && -t 0 ]]; then
  if [[ -f "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/fzf/shell/completion.zsh" ]]; then
    source "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/fzf/shell/completion.zsh"
  fi
  if [[ -f "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/fzf/shell/key-bindings.zsh" ]]; then
    source "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/fzf/shell/key-bindings.zsh"
  fi
fi

# direnv — explicit per-repo env loading. Requires `direnv allow` in each repo.
if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook zsh)"
fi

# Make Homebrew's Compose and Buildx discoverable without starting Colima.
for docker_plugin in docker-compose docker-buildx; do
  docker_source="${HOMEBREW_PREFIX:-/opt/homebrew}/lib/docker/cli-plugins/$docker_plugin"
  docker_target="$HOME/.docker/cli-plugins/$docker_plugin"
  if [[ -x "$docker_source" && ! -e "$docker_target" ]]; then
    mkdir -p "$HOME/.docker/cli-plugins" && ln -sfn "$docker_source" "$docker_target"
  fi
done
unset docker_plugin docker_source docker_target
