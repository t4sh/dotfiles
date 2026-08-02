#!/usr/bin/env bash
# Idempotent, restore-first GitHub SSH bootstrap.
#   1. Require the vault-restored Ed25519 key (unless --generate is explicit)
#   2. validate the private/public pair and chmod tightly
#   3. Add to ssh-agent with Apple Keychain integration
#   4. Verify the exact key with GitHub
#   5. Converge GitHub authentication and SSH signing registrations separately
#
# Tower, VS Code, Cursor, and any CLI git will all pick up the same key through
# the macOS ssh-agent — no separate "sync to Tower" step is needed.

set -euo pipefail

SECRETS_DIR="${DOTFILES_SECRETS_DIR:-$HOME/.secrets/ssh}"
KEY="$SECRETS_DIR/github_ed25519"
KNOWN_HOSTS="$HOME/.ssh/known_hosts"
EMAIL="${GIT_EMAIL:-$(git config --global user.email 2>/dev/null || true)}"
LABEL="${SSH_KEY_LABEL:-$(scutil --get ComputerName 2>/dev/null || hostname -s) $(date +%Y-%m)}"
GITHUB_HOST="github.com"
# This workflow verifies git@github.com, so every gh read/write must target the
# same service even when the caller has GH_HOST set for an enterprise session.
export GH_HOST="$GITHUB_HOST"
GENERATE=0

case "${1:-}" in
  "") ;;
  --generate) GENERATE=1 ;;
  -h|--help)
    echo "usage: $0 [--generate]"
    echo "  default: restore/verify an existing vault-backed key"
    echo "  --generate: explicitly create a new canonical GitHub key when no vault key exists"
    exit 0
    ;;
  *) echo "unknown option: $1" >&2; exit 1 ;;
esac

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  ⚠\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# 1. Restore-first key handling. Generation requires an explicit flag so a
# pre-vault bootstrap cannot create and upload a throwaway canonical key.
if [[ ! -f "$KEY" && $GENERATE -ne 1 ]]; then
  die "vault-backed GitHub key not found: $KEY
  restore ~/.secrets first, or explicitly create a new identity with:
  bash scripts/ssh-setup.sh --generate"
fi
mkdir -p "$SECRETS_DIR" && chmod 700 "$SECRETS_DIR"
if [[ ! -f "$KEY" ]]; then
  [[ -n "$EMAIL" ]] || die "git user.email is not configured — run: git config --global user.email you@example.com"
  info "explicitly generating Ed25519 → $KEY"
  ssh-keygen -t ed25519 -C "$EMAIL" -f "$KEY" -N ""
  ok "key generated"
else
  ok "key already present: $KEY"
fi
chmod 600 "$KEY"
if [[ ! -f "$KEY.pub" ]]; then
  ssh-keygen -y -f "$KEY" > "$KEY.pub"
  ok "reconstructed missing public key"
fi
chmod 644 "$KEY.pub"

EXPECTED_PUB="$(ssh-keygen -y -f "$KEY" | awk '{print $1, $2}')"
STORED_PUB="$(awk '{print $1, $2}' "$KEY.pub")"
[[ "$EXPECTED_PUB" == "$STORED_PUB" ]] || die "public key does not match private key: $KEY.pub"

# 2. Exact proof is noninteractive and ignores SSH config, so first establish
# host trust from the vault-backed known_hosts file before touching ssh-agent or
# GitHub's API. `ssh-keygen -F` supports both plain and hashed host entries.
if [[ ! -f "$KNOWN_HOSTS" ]] || \
   ! ssh-keygen -F "$GITHUB_HOST" -f "$KNOWN_HOSTS" >/dev/null 2>&1; then
  die "GitHub host trust is missing from $KNOWN_HOSTS
  restore ~/.secrets/ssh/known_hosts, run 'make link', and retry
  for a deliberately new identity, verify GitHub's published SSH fingerprints,
  establish trust for github.com once, then retry"
fi
ok "GitHub host trust present in $KNOWN_HOSTS"

# 3. ~/.ssh/config sanity — should already be the symlink from make link
if [[ ! -L "$HOME/.ssh/config" ]]; then
  warn "$HOME/.ssh/config is not a symlink; run 'make link' first for the dotfiles config"
fi

# 4. Add to ssh-agent + Apple Keychain (Ed25519 without passphrase is a no-op
#    for Keychain; kept for future keys that may carry one).
info "registering with ssh-agent"
if ssh-add --apple-use-keychain "$KEY" >/dev/null 2>&1; then
  ok "ssh-agent updated with Apple Keychain integration"
elif ssh-add "$KEY" >/dev/null 2>&1; then
  warn "ssh-agent updated without Apple Keychain integration"
else
  die "could not add $KEY to ssh-agent"
fi

verify_github_key() {
  local output status
  set +e
  output="$(ssh -F none -T -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes \
    -o ConnectTimeout=10 git@github.com 2>&1)"
  status=$?
  set -e
  VERIFY_OUTPUT="$output"
  VERIFY_STATUS=$status
  VERIFY_LOGIN=""
  if [[ "$output" == *"successfully authenticated"* ]]; then
    VERIFY_LOGIN="$(printf '%s\n' "$output" | sed -n 's/^Hi \([^!]*\)!.*successfully authenticated.*$/\1/p' | head -n 1)"
    return 0
  fi
  return 1
}

# 5. Verify the exact authentication registration before using the API.
SSH_VERIFIED=0
info "verifying the exact key with GitHub"
if verify_github_key; then
  printf '%s\n' "$VERIFY_OUTPUT" | sed -n '1,2p'
  ok "public key already registered and authenticating"
  SSH_VERIFIED=1
fi

# 6. Authentication and signing are separate GitHub registrations. The same
# public key must be present in both stores, so signing convergence always needs
# an authenticated gh CLI even when the SSH handshake already succeeds.
command -v gh >/dev/null 2>&1 || die "gh CLI not found — install via: brew install gh"
gh auth status --hostname "$GITHUB_HOST" >/dev/null 2>&1 || \
  die "gh is not authenticated for $GITHUB_HOST — run: gh auth login -h $GITHUB_HOST"
if ! GH_LOGIN="$(gh api user --jq .login 2>&1)" || [[ -z "$GH_LOGIN" ]]; then
  printf '%s\n' "$GH_LOGIN" >&2
  die "cannot determine the active gh account — run: gh auth status"
fi
if (( SSH_VERIFIED )); then
  [[ -n "$VERIFY_LOGIN" ]] || die "GitHub SSH authentication succeeded but its account could not be parsed"
  [[ "$VERIFY_LOGIN" == "$GH_LOGIN" ]] || die \
    "the exact SSH key and gh CLI use different GitHub accounts (SSH: $VERIFY_LOGIN; gh: $GH_LOGIN)
  switch gh to $VERIFY_LOGIN or correct ~/.ssh/config before retrying"
fi

key_list_contains_expected() {
  local key_line normalized
  while IFS= read -r key_line; do
    normalized="$(printf '%s\n' "$key_line" | awk '{print $1, $2}')"
    [[ "$normalized" == "$EXPECTED_PUB" ]] && return 0
  done
  return 1
}

list_github_keys() {
  local endpoint="$1" label="$2" scope="$3" output
  if ! output="$(gh api --paginate "$endpoint" --jq '.[].key' 2>&1)"; then
    printf '%s\n' "$output" >&2
    die "cannot query GitHub $label keys; run: gh auth refresh -h github.com -s $scope"
  fi
  GITHUB_KEY_LIST="$output"
}

list_github_keys user/keys authentication read:public_key
if key_list_contains_expected <<< "$GITHUB_KEY_LIST"; then
  ok "authentication key already listed for gh account $GH_LOGIN"
else
  if (( SSH_VERIFIED )); then
    die "the authenticating SSH key is not listed for active gh account $GH_LOGIN; refusing remote mutation"
  else
    info "uploading authentication key to GitHub (label: $LABEL)"
    gh ssh-key add "$KEY.pub" --title "$LABEL" --type authentication || \
      die "GitHub authentication-key upload failed; refresh gh's write:public_key scope and retry"
    ok "authentication key added to GitHub"
  fi
fi

if (( ! SSH_VERIFIED )); then
  info "verifying authentication key with GitHub"
  if verify_github_key; then
    printf '%s\n' "$VERIFY_OUTPUT" | sed -n '1,2p'
    [[ -n "$VERIFY_LOGIN" ]] || die "GitHub SSH authentication succeeded but its account could not be parsed"
    [[ "$VERIFY_LOGIN" == "$GH_LOGIN" ]] || die \
      "the exact SSH key and gh CLI use different GitHub accounts (SSH: $VERIFY_LOGIN; gh: $GH_LOGIN)"
    ok "GitHub SSH authentication verified"
    SSH_VERIFIED=1
  else
    die "GitHub SSH verification failed (status $VERIFY_STATUS)"
  fi
fi

list_github_keys user/ssh_signing_keys signing read:ssh_signing_key
if key_list_contains_expected <<< "$GITHUB_KEY_LIST"; then
  ok "SSH signing key already registered on GitHub"
else
  info "uploading SSH signing key to GitHub (label: $LABEL)"
  gh ssh-key add "$KEY.pub" --title "$LABEL (signing)" --type signing || \
    die "GitHub signing-key upload failed; refresh gh's write:ssh_signing_key scope and retry"
  list_github_keys user/ssh_signing_keys signing read:ssh_signing_key
  key_list_contains_expected <<< "$GITHUB_KEY_LIST" || \
    die "GitHub accepted the signing-key upload but it is not present on re-query"
  ok "SSH signing key added to GitHub"
fi

ok "Tower / VS Code / git CLI share this verified authentication and signing key via ssh-agent"
