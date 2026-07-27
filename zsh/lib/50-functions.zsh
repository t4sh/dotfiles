# Shell functions — stateful helpers that need current-shell context.

# Make a directory and cd into it.
mcd() {
  [[ -z "$1" ]] && echo "Usage: mcd <dir>" && return 1
  mkdir -p -- "$1" && cd -- "$1"
}

# Fuzzy cd into a project under ~/Projects. `bin/j` opens projects in an editor;
# this one changes the current shell directory.
jcd() {
  local root="${PROJECTS_DIR:-$HOME/Projects}"
  local project
  [[ -d "$root" ]] || { echo "Projects directory not found: $root"; return 1; }
  command -v fzf >/dev/null 2>&1 || { echo "fzf is required for jcd"; return 1; }

  if command -v fd >/dev/null 2>&1; then
    project=$(fd . "$root" --type d --max-depth 3 --hidden --exclude .git --exclude node_modules | fzf --prompt='project> ')
  else
    project=$(find "$root" -maxdepth 3 -type d | fzf --prompt='project> ')
  fi

  [[ -n "$project" ]] && cd -- "$project"
}

# Free a port by killing whatever is listening on it.
free-port() {
  [[ -z "$1" ]] && echo "Usage: free-port <port>" && return 1
  if lsof -i :$1 >/dev/null 2>&1; then
    echo "Port $1 in use. Killing processes..."
    lsof -t -i :$1 | xargs kill -9
    echo "Port $1 freed."
  else
    echo "No process on port $1."
  fi
}

# Free multiple ports.
free-ports() {
  for port in "$@"; do
    free-port $port
  done
}

# List listening ports.
list-ports() {
  echo "Listening ports:"
  sudo lsof -iTCP -sTCP:LISTEN -P -n | grep -E 'COMMAND|localhost|\*:' | sort -u
}

# Auto-switch Node from the nearest parent .nvmrc and restore the dotfiles pin
# after leaving that project tree. Keep the default fast PATH untouched until a
# project actually requires NVM.
typeset -g AUTO_NVM_ACTIVE=0

find_nvmrc_up() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.nvmrc" ]]; then
      print -r -- "$dir/.nvmrc"
      return 0
    fi
    dir="${dir:h}"
  done
  return 1
}

auto_nvm_use() {
  local nvmrc requested default_version
  if nvmrc="$(find_nvmrc_up)"; then
    requested="$(tr -d '[:space:]' < "$nvmrc")"
    if [[ -n "$requested" ]]; then
      nvm use --silent "$requested" || return 1
      AUTO_NVM_ACTIVE=1
    fi
  elif (( AUTO_NVM_ACTIVE )); then
    default_version="$(tr -d '[:space:]' < "$HOME/.dotfiles/.node-version")"
    if [[ -n "$default_version" ]]; then
      nvm use --silent "$default_version" || return 1
      AUTO_NVM_ACTIVE=0
    fi
  fi
}
