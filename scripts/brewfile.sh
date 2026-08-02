#!/usr/bin/env bash
# Phased Brewfile operations. npm globals always run under .node-version, and
# retired App Store receipts are kept out of the declarative Brewfile.
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
BREWFILE="${BREWFILE:-$DOTFILES/Brewfile}"
RETIRED_MAS_IDS="${DOTFILES_RETIRED_MAS_IDS:-$DOTFILES/config/retired-mas-ids.tsv}"
NODE_VERSION_FILE="${DOTFILES_NODE_VERSION_FILE:-$DOTFILES/.node-version}"

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
usage: scripts/brewfile.sh {base|npm|mas|check|dump <destination>}

  base   install formulae, casks, taps, fonts, and editor extensions
  npm    install npm globals under the pinned .node-version runtime
  mas    install current App Store declarations only
  check  check the full Brewfile with pinned Node active
  dump   generate a Brewfile, filtering explicitly retired MAS receipts
EOF
}

[[ -f "$BREWFILE" ]] || die "Brewfile not found: $BREWFILE"
[[ -f "$RETIRED_MAS_IDS" ]] || die "retired MAS manifest not found: $RETIRED_MAS_IDS"

assert_retired_mas_absent() {
  local violations
  violations="$(awk -F '\t' '
    NR == FNR { if ($1 !~ /^#/ && $1 ~ /^[0-9]+$/) retired[$1] = 1; next }
    /^[[:space:]]*mas[[:space:]]/ {
      for (id in retired) {
        if ($0 ~ ("id:[[:space:]]*" id "([^0-9]|$)")) print FNR ":" $0
      }
    }
  ' "$RETIRED_MAS_IDS" "$BREWFILE")"
  [[ -z "$violations" ]] || die "Brewfile contains retired App Store IDs:
$violations"
}

activate_pinned_node() {
  local node_pinned nvm_sh
  [[ -f "$NODE_VERSION_FILE" ]] || die "Node version file not found: $NODE_VERSION_FILE"
  node_pinned="$(tr -d '[:space:]' < "$NODE_VERSION_FILE")"
  [[ -n "$node_pinned" ]] || die "Node version file is empty: $NODE_VERSION_FILE"
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  nvm_sh="${DOTFILES_NVM_SH:-$(brew --prefix 2>/dev/null)/opt/nvm/nvm.sh}"
  [[ -s "$nvm_sh" ]] || die "nvm.sh not found: $nvm_sh (run: make node)"
  # shellcheck disable=SC1090
  . "$nvm_sh"
  nvm use --silent "$node_pinned" >/dev/null || die "pinned Node $node_pinned is not installed (run: make node)"
}

filter_retired_mas() {
  local input="$1" output="$2"
  awk -F '\t' '
    NR == FNR { if ($1 !~ /^#/ && $1 ~ /^[0-9]+$/) retired[$1] = 1; next }
    {
      skip = 0
      if ($0 ~ /^[[:space:]]*mas[[:space:]]/) {
        for (id in retired) {
          if ($0 ~ ("id:[[:space:]]*" id "([^0-9]|$)")) { skip = 1; break }
        }
      }
      if (!skip) print
    }
  ' "$RETIRED_MAS_IDS" "$input" > "$output"
}

assert_retired_mas_absent

case "${1:-}" in
  base)
    awk '!/^[[:space:]]*(mas|npm)[[:space:]]+/' "$BREWFILE" | brew bundle --file=-
    ;;
  npm)
    activate_pinned_node
    awk '/^[[:space:]]*npm[[:space:]]+/' "$BREWFILE" | brew bundle --file=-
    ;;
  mas)
    command -v mas >/dev/null 2>&1 || die "mas missing; run: make brew-base"
    awk '/^[[:space:]]*mas[[:space:]]+/' "$BREWFILE" | brew bundle --file=-
    ;;
  check)
    activate_pinned_node
    brew bundle check --file="$BREWFILE"
    ;;
  dump)
    [[ -n "${2:-}" ]] || die "dump requires a destination path"
    activate_pinned_node
    destination_dir="$(dirname "$2")"
    mkdir -p "$destination_dir"
    tmp="$(mktemp "${TMPDIR:-/tmp}/dotfiles-brewfile.XXXXXX")"
    filtered="$(mktemp "$destination_dir/.dotfiles-brewfile-filtered.XXXXXX")"
    cleanup_dump() {
      rm -f -- "$tmp"
      [[ -z "$filtered" ]] || rm -f -- "$filtered"
    }
    trap cleanup_dump EXIT HUP INT TERM
    brew bundle dump --file="$tmp" --force
    filter_retired_mas "$tmp" "$filtered"
    mv "$filtered" "$2"
    filtered=""
    ;;
  -h|--help|help) usage ;;
  *) usage >&2; exit 1 ;;
esac
