# Secrets are loaded only for interactive shells. Independently launched
# non-interactive zsh commands stay deterministic; children still inherit any
# values already exported by their interactive parent shell.
if [[ -o interactive && -f "$HOME/.secrets/env.sh" ]]; then
  source "$HOME/.secrets/env.sh"
fi
