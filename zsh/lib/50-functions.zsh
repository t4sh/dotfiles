# Shell functions — stateful helpers that need current-shell context.

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
