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

# Auto-switch node version when entering a directory with .nvmrc
auto_nvm_use() {
  [ -f .nvmrc ] && nvm use --silent
}
