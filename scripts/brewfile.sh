#!/usr/bin/env bash
# Phased Brewfile operations. npm globals always run under .node-version, and
# retired App Store receipts are kept out of the declarative Brewfile.
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
BREWFILE="${BREWFILE:-$DOTFILES/Brewfile}"
RETIRED_MAS_IDS="${DOTFILES_RETIRED_MAS_IDS:-$DOTFILES/config/retired-mas-ids.tsv}"
NODE_VERSION_FILE="${DOTFILES_NODE_VERSION_FILE:-$DOTFILES/.node-version}"

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
warn() { printf '\033[33m  ⚠\033[0m %s\n' "$*"; }

usage() {
  cat <<'EOF'
usage: scripts/brewfile.sh {core|apps|base|npm|mas|mas-optional|check|dump <destination>}

  core   install taps and formulae required by the bootstrap
  apps   install casks, fonts, and editor extensions
  base   run core, then apps (backward-compatible strict aggregate)
  npm    install npm globals under the pinned .node-version runtime
  mas    install current App Store declarations only
  mas-optional  confirm App Store readiness interactively; otherwise defer
  check  check installed Brewfile entries with pinned Node active
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

merge_curated_declarations() {
  local curated="$1" dumped="$2" output="$3"
  awk '
    function declaration_key(line, normalized, kind, rest, name) {
      normalized = line
      sub(/^[[:space:]]*/, "", normalized)
      if (normalized !~ /^(tap|brew|cask|mas|vscode|npm)[[:space:]]+"/) return ""
      kind = normalized
      sub(/[[:space:]].*$/, "", kind)
      rest = normalized
      sub(/^[^"]*"/, "", rest)
      name = rest
      sub(/".*$/, "", name)
      return kind SUBSEP name
    }
    NR == FNR {
      key = declaration_key($0)
      if (key != "") curated[key] = $0
      next
    }
    {
      key = declaration_key($0)
      if (key != "" && key in curated) print curated[key]
      else print
    }
  ' "$curated" "$dumped" > "$output"
}

check_installed_entries() {
  DOTFILES_CHECK_FILTERED="$(mktemp "${TMPDIR:-/tmp}/dotfiles-brew-check.XXXXXX")"
  DOTFILES_CHECK_EXPECTED="$(mktemp "${TMPDIR:-/tmp}/dotfiles-brew-expected.XXXXXX")"
  DOTFILES_CHECK_ACTUAL="$(mktemp "${TMPDIR:-/tmp}/dotfiles-brew-actual.XXXXXX")"
  DOTFILES_CHECK_MISSING="$(mktemp "${TMPDIR:-/tmp}/dotfiles-brew-missing.XXXXXX")"
  trap 'rm -f -- "$DOTFILES_CHECK_FILTERED" "$DOTFILES_CHECK_EXPECTED" "$DOTFILES_CHECK_ACTUAL" "$DOTFILES_CHECK_MISSING"' EXIT HUP INT TERM

  # Homebrew Bundle may select a VS Code-family launcher other than `code`, and
  # its MAS check treats pending updates as missing. Keep Bundle responsible for
  # the package types it can identify reliably, then check these two inventories
  # directly. Bootstrap completeness means declared entries are present; day-2
  # upgrades remain topgrade/Homebrew's responsibility.
  awk '!/^[[:space:]]*(vscode|mas)[[:space:]]+/' "$BREWFILE" > "$DOTFILES_CHECK_FILTERED"
  brew bundle check --no-upgrade --file="$DOTFILES_CHECK_FILTERED"

  awk -F '"' '/^[[:space:]]*vscode[[:space:]]+/ { print tolower($2) }' "$BREWFILE" \
    | LC_ALL=C sort -u > "$DOTFILES_CHECK_EXPECTED"
  if [[ -s "$DOTFILES_CHECK_EXPECTED" ]]; then
    command -v code >/dev/null 2>&1 || die "VS Code CLI missing; run: make brew-apps"
    code --list-extensions \
      | tr '[:upper:]' '[:lower:]' \
      | LC_ALL=C sort -u > "$DOTFILES_CHECK_ACTUAL" || die "could not query installed VS Code extensions"
    comm -23 "$DOTFILES_CHECK_EXPECTED" "$DOTFILES_CHECK_ACTUAL" > "$DOTFILES_CHECK_MISSING"
    [[ ! -s "$DOTFILES_CHECK_MISSING" ]] || die "declared VS Code extensions missing:
$(sed 's/^/  - /' "$DOTFILES_CHECK_MISSING")"
  fi

  sed -nE 's/^[[:space:]]*mas[[:space:]].*id:[[:space:]]*([0-9]+).*$/\1/p' "$BREWFILE" \
    | LC_ALL=C sort -u > "$DOTFILES_CHECK_EXPECTED"
  if [[ -s "$DOTFILES_CHECK_EXPECTED" ]]; then
    command -v mas >/dev/null 2>&1 || die "mas missing; run: make brew-base"
    mas list \
      | awk '$1 ~ /^[0-9]+$/ { print $1 }' \
      | LC_ALL=C sort -u > "$DOTFILES_CHECK_ACTUAL" || die "could not query installed App Store receipts"
    comm -23 "$DOTFILES_CHECK_EXPECTED" "$DOTFILES_CHECK_ACTUAL" > "$DOTFILES_CHECK_MISSING"
    [[ ! -s "$DOTFILES_CHECK_MISSING" ]] || die "declared App Store apps missing (IDs):
$(sed 's/^/  - /' "$DOTFILES_CHECK_MISSING")"
  fi

  echo "The Brewfile's declared entries are installed."
}

run_optional_mas() {
  local readiness="${DOTFILES_MAS_SIGNED_IN:-}" reply=""

  case "$readiness" in
    1|true|yes) DOTFILES="$DOTFILES" BREWFILE="$BREWFILE" "$0" mas; return ;;
    0|false|no)
      warn "App Store phase deferred; sign in, then run: make brew-mas"
      return
      ;;
    '') ;;
    *) die "DOTFILES_MAS_SIGNED_IN must be 1/0, true/false, or yes/no" ;;
  esac

  # mas 7 has no supported account-status command. `mas list` only reads local
  # receipts and succeeds while signed out, so do not pretend it is a sign-in
  # probe. Ask in an interactive shell and fail open to the documented explicit
  # follow-on everywhere else.
  if [[ -t 0 ]]; then
    printf '→ App Store signed in; run the MAS phase now? (y/N) '
    IFS= read -r reply || reply=""
  fi
  if [[ "$reply" =~ ^[Yy]$ ]]; then
    DOTFILES="$DOTFILES" BREWFILE="$BREWFILE" "$0" mas
  else
    warn "App Store phase deferred; sign in, then run: make brew-mas"
  fi
}

assert_retired_mas_absent

case "${1:-}" in
  core)
    awk '/^[[:space:]]*(tap|brew)[[:space:]]+/' "$BREWFILE" | brew bundle --file=-
    ;;
  apps)
    awk '/^[[:space:]]*(tap|cask|vscode|cask_args)[[:space:]]+/' "$BREWFILE" | brew bundle --file=-
    ;;
  base)
    DOTFILES="$DOTFILES" BREWFILE="$BREWFILE" "$0" core
    DOTFILES="$DOTFILES" BREWFILE="$BREWFILE" "$0" apps
    ;;
  npm)
    activate_pinned_node
    awk '/^[[:space:]]*npm[[:space:]]+/' "$BREWFILE" | brew bundle --file=-
    ;;
  mas)
    command -v mas >/dev/null 2>&1 || die "mas missing; run: make brew-base"
    awk '/^[[:space:]]*mas[[:space:]]+/' "$BREWFILE" | brew bundle --file=-
    ;;
  mas-optional)
    run_optional_mas
    ;;
  check)
    activate_pinned_node
    check_installed_entries
    ;;
  dump)
    [[ -n "${2:-}" ]] || die "dump requires a destination path"
    activate_pinned_node
    destination_dir="$(dirname "$2")"
    mkdir -p "$destination_dir"
    tmp="$(mktemp "${TMPDIR:-/tmp}/dotfiles-brewfile.XXXXXX")"
    filtered="$(mktemp "$destination_dir/.dotfiles-brewfile-filtered.XXXXXX")"
    merged="$(mktemp "$destination_dir/.dotfiles-brewfile-merged.XXXXXX")"
    cleanup_dump() {
      rm -f -- "$tmp"
      [[ -z "$filtered" ]] || rm -f -- "$filtered"
      [[ -z "$merged" ]] || rm -f -- "$merged"
    }
    trap cleanup_dump EXIT HUP INT TERM
    brew bundle dump --file="$tmp" --force
    filter_retired_mas "$tmp" "$filtered"
    merge_curated_declarations "$BREWFILE" "$filtered" "$merged"
    mv "$merged" "$2"
    merged=""
    ;;
  -h|--help|help) usage ;;
  *) usage >&2; exit 1 ;;
esac
