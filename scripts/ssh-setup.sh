#!/usr/bin/env bash
# Idempotent GitHub SSH bootstrap.
#   1. Generate Ed25519 at ~/.secrets/ssh/github_ed25519 (if missing)
#   2. chmod tightly
#   3. Add to ssh-agent with Apple Keychain integration
#   4. Verify the exact key with GitHub
#   5. Upload via gh only when verification proves registration is missing
#
# Tower, VS Code, Cursor, and any CLI git will all pick up the same key through
# the macOS ssh-agent — no separate "sync to Tower" step is needed.

set -euo pipefail

SECRETS_DIR="${DOTFILES_SECRETS_DIR:-$HOME/.secrets/ssh}"
KEY="$SECRETS_DIR/github_ed25519"
EMAIL="${GIT_EMAIL:-$(git config --global user.email 2>/dev/null || true)}"
LABEL="${SSH_KEY_LABEL:-$(scutil --get ComputerName 2>/dev/null || hostname -s) $(date +%Y-%m)}"

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  ⚠\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[[ -n "$EMAIL" ]] || die "git user.email is not configured — run: git config --global user.email you@example.com"

# 1. Generate key if missing
mkdir -p "$SECRETS_DIR" && chmod 700 "$SECRETS_DIR"
if [[ ! -f "$KEY" ]]; then
  info "generating Ed25519 → $KEY"
  ssh-keygen -t ed25519 -C "$EMAIL" -f "$KEY" -N ""
  ok "key generated"
else
  ok "key already present: $KEY"
fi
chmod 600 "$KEY"
chmod 644 "$KEY.pub"

# 2. ~/.ssh/config sanity — should already be the symlink from make link
if [[ ! -L "$HOME/.ssh/config" ]]; then
  warn "$HOME/.ssh/config is not a symlink; run 'make link' first for the dotfiles config"
fi

# 3. Add to ssh-agent + Apple Keychain (Ed25519 without passphrase is a no-op
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
  output="$(ssh -T -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes \
    -o ConnectTimeout=10 git@github.com 2>&1)"
  status=$?
  set -e
  VERIFY_OUTPUT="$output"
  VERIFY_STATUS=$status
  [[ "$output" == *"successfully authenticated"* ]]
}

# 4. Verify the exact key before using the API. This avoids requiring the
# admin:public_key scope when the key is already registered.
SSH_VERIFIED=0
info "verifying the exact key with GitHub"
if verify_github_key; then
  printf '%s\n' "$VERIFY_OUTPUT" | sed -n '1,2p'
  ok "public key already registered and authenticating"
  SSH_VERIFIED=1
fi

# 5. Upload only when verification proves the key is not registered.
if (( ! SSH_VERIFIED )); then
  if ! command -v gh >/dev/null 2>&1; then
    die "gh CLI not found — install via: brew install gh"
  fi
  if ! gh auth status >/dev/null 2>&1; then
    warn "gh not authenticated — GitHub key upload and verification pending"
    warn "after GitHub auth, re-run: make ssh-setup"
  else
    if ! key_list="$(gh ssh-key list 2>&1)"; then
      printf '%s\n' "$key_list" >&2
      die "cannot query GitHub SSH keys; run: gh auth refresh -h github.com -s admin:public_key"
    fi

    PUB_PREFIX="$(awk '{print $1, $2}' "$KEY.pub")"
    if printf '%s\n' "$key_list" | cut -f2 | grep -qxF "$PUB_PREFIX"; then
      ok "public key already listed on GitHub"
    else
      info "uploading public key to GitHub (label: $LABEL)"
      gh ssh-key add "$KEY.pub" --title "$LABEL" || \
        die "GitHub key upload failed; refresh gh's admin:public_key scope and retry"
      ok "key added to GitHub"
    fi

    info "verifying uploaded key with GitHub"
    if verify_github_key; then
      printf '%s\n' "$VERIFY_OUTPUT" | sed -n '1,2p'
      ok "GitHub SSH authentication verified"
      SSH_VERIFIED=1
    else
      die "GitHub SSH verification failed (status $VERIFY_STATUS)"
    fi
  fi
fi

if (( SSH_VERIFIED )); then
  ok "Tower / VS Code / git CLI share this verified key via ssh-agent"
else
  warn "local key is loaded, but GitHub registration is still pending"
fi
