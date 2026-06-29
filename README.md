# dotfiles

Personal Mac bootstrap and configuration system.

This public repo contains non-secret configuration snapshots and reusable Mac setup automation: shell config, Git config, Starship themes, package manifests, app preference snapshots, macOS defaults, Automator services, and AI agent rules/skills that are safe to redistribute.

Secrets are not stored here. API keys, SSH private keys, auth files, licensed app settings, and app export bundles belong under `~/.secrets/` and can be backed up with the encrypted vault workflow.

## Fresh Mac

```bash
git clone https://github.com/t4sh/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
bash install.sh
```

`install.sh` installs Xcode CLI tools, Homebrew packages, symlinks, app preferences, Automator services, optional macOS/Dock settings, optional GitHub SSH setup, and git hooks.

## Existing Mac

```bash
cd ~/.dotfiles
make all
```

`make all` runs `link`, `skills-audit`, `brew`, `services`, `restore-apps`, `dock`, `hooks`, `ssh-setup`, and `macos`. Terminal profile import is manual because it quits Terminal.app.

## Common Targets

```bash
make link            # Apply symlinks from symlinks.tsv
make brew            # Install Brewfile packages
make restore-apps    # Restore tracked app prefs
make services        # Install Automator workflows
make macos           # Apply macOS defaults
make dock            # Restore Dock layout
make terminal        # Import Terminal.app profiles
make ssh-setup       # Create/register GitHub SSH key
make backup          # Refresh tracked snapshots from this Mac
make secrets-backup  # Snapshot ~/.secrets into encrypted sparseimage
make all             # Main re-apply target
```

## Layout

| Path | Purpose |
|---|---|
| `Brewfile` | Homebrew, casks, fonts, VS Code extensions, npm globals |
| `symlinks.tsv` | Declarative source-to-target symlink manifest |
| `zsh/` | Shell configuration |
| `git/` | Git config and global ignore |
| `starship/` | Prompt themes |
| `config/` | Non-secret tool configs |
| `agents/` | Public-safe agent rules, skills, commands, and agents |
| `apps/` | Non-secret app preference snapshots |
| `macos/` | macOS defaults and Dock layout |
| `services/` | Automator Quick Actions |
| `scripts/` | Bootstrap, backup, restore, audit, and vault helpers |

## Secrets

`~/.secrets/` is the expected local-only tree for credentials and licensed settings. It is intentionally ignored by git.

Recommended layout:

```text
~/.secrets/
├── env.sh
├── ssh/
├── config/
│   ├── gh/hosts.yml
│   └── moltbook/credentials.json
└── apps/
    ├── canary-mail/
    ├── raycast/
    ├── sublime-text/
    └── transmit/
```

The vault helpers use an encrypted sparseimage and a Keychain-stored passphrase:

```bash
make secrets-backup
make secrets-mount
make secrets-pass
```

## Safety Gates

- `gitleaks` blocks new secrets in commits.
- `scripts/audit-app-prefs.sh` scans app/macOS snapshots for tokens, license keys, emails, and hardcoded home paths.
- `scripts/audit-skill-licenses.sh` blocks non-redistributable skills from being tracked.
- `scripts/verify-idempotency.sh` checks that repeated setup converges.
