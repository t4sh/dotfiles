# Exports — values only. PATH entries live in 00-path.zsh and 60-tools.zsh.

export NVM_DIR="$HOME/.nvm"
export PNPM_HOME="$HOME/Library/pnpm"

# Per-tool .env files autoloaded by consumer tools (direnv etc.)
export ENV_DIR="$HOME/.config/env"
# recommended permissions:
#   chmod 755 ~/.config
#   chmod -R go+rX,u+rwX ~/.config

# Modern CLI defaults.
export BAT_THEME="TwoDark"
export BAT_STYLE="numbers,changes,header"

export FZF_DEFAULT_COMMAND="fd --hidden --strip-cwd-prefix --exclude .git"
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND="fd --type d --hidden --strip-cwd-prefix --exclude .git"
export FZF_DEFAULT_OPTS="--height=40% --layout=reverse --border --info=inline --cycle"
export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:200 {} 2>/dev/null || ls -la {}'"
export FZF_ALT_C_OPTS="--preview 'eza --tree --level=2 --icons=auto --color=always {} 2>/dev/null || ls -la {}'"
