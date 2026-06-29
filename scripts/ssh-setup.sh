#!/usr/bin/env bash
# Idempotent GitHub SSH bootstrap.
#   1. Generate Ed25519 at ~/.secrets/ssh/github_ed25519 (if missing)
#   2. chmod tightly
#   3. Add to ssh-agent with Apple Keychain integration
#   4. Upload public key to GitHub via gh CLI
#   5. Verify with `ssh -T git@github.com`
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
ssh-add --apple-use-keychain "$KEY" 2>/dev/null || true
ok "ssh-agent updated"

# 4. Upload public key to GitHub via gh (skip if already registered)
if ! command -v gh >/dev/null 2>&1; then
  die "gh CLI not found — install via: brew install gh"
fi
if ! gh auth status >/dev/null 2>&1; then
  warn "gh not authenticated — skipping GitHub key upload"
  warn "after GitHub auth, re-run: make ssh-setup"
else
  # Match on `ssh-ed25519 <base64>` — the comment (email) field isn't stored by
  # GitHub, so we compare only the type + body. gh ssh-key list is tab-separated;
  # field 2 is the key itself.
  PUB_PREFIX="$(awk '{print $1, $2}' "$KEY.pub")"
  if gh ssh-key list 2>/dev/null | cut -f2 | grep -qxF "$PUB_PREFIX"; then
    ok "public key already registered on GitHub — skipping upload"
  else
    info "uploading public key to GitHub (label: $LABEL)"
    gh ssh-key add "$KEY.pub" --title "$LABEL" && ok "key added to GitHub"
  fi
fi

# 5. Verify
info "verifying ssh -T git@github.com"
ssh -T git@github.com 2>&1 | head -2 || true
ok "done — Tower / VS Code / git CLI will all share this key via ssh-agent"
