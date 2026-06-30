# dotfiles

**macOS bootstrap and dotfiles** — an idempotent Mac setup system, not just shell aliases.

This repo is a **fork-friendly**, public snapshot of a personal Mac factory: declarative symlinks, a single Brewfile, app preference snapshots, macOS defaults, Automator services, safety audits, and a redistributable **AI agent rules/skills** tree. It sits in the same family as [holman](https://github.com/holman/dotfiles), [mathiasbynens](https://github.com/mathiasbynens/dotfiles), and [nicksp](https://github.com/nicksp/dotfiles) — but with heavier **ops, verification, and agent-era** coverage than most dotfiles repos.

> **Fork, don't run blind.** This is one person's Mac policy (editors, default apps, Dock, agents). Clone it, delete what you don't use, and make it yours — the structure is meant to be adapted, not consumed verbatim.

## Why this repo (vs typical dotfiles)

Most [awesome-dotfiles](https://github.com/webpro/awesome-dotfiles) examples stop at zsh + Homebrew + a `.macos` script. This one adds:

| Area | Typical dotfiles | This repo |
|------|------------------|-----------|
| Symlinks | Stow, dotbot, rcm, chezmoi | [`symlinks.tsv`](symlinks.tsv) + `make link` — add a row, no extra framework |
| Fresh Mac | `setup.sh` or `script/bootstrap` | [`install.sh`](install.sh) (from zero) + [`make all`](Makefile) (re-apply) |
| Packages | Brewfile | Brewfile as **single source of truth** (formulae, casks, MAS, VS Code extensions) |
| App prefs | mackup or manual | [`apps.tsv`](apps.tsv) + `make backup` / `make restore-apps`; licensed prefs in vault |
| Default apps | Rare | [`config/duti`](config/duti) as **repo policy** → `make default-apps` |
| Secrets | `*.local` files | `~/.secrets/` + encrypted sparseimage (`make secrets-backup`) |
| Verification | Uncommon | `make doctor`, `brewfile-audit`, `verify-idempotency.sh`, gitleaks |
| AI agents | Emerging (e.g. nicksp) | Whole [`agents/`](agents/) tree, skills lockfile, license gate |

**Scope:** macOS only. No chezmoi/yadm templating — per-machine overrides go in gitignored `zsh/lib/99-local.zsh`.

## Requirements

- macOS (Apple Silicon or Intel)
- Xcode Command Line Tools (`install.sh` can prompt to install)
- Homebrew (`install.sh` can install it)
- zsh as login shell (`install.sh` sets this)

## What's included

- **Shell** — modular zsh ([`zsh/lib/`](zsh/lib/)), Starship themes, [`bin/dot`](bin/dot) script dispatcher, [`bin/j`](bin/j) project opener
- **Packages** — [`Brewfile`](Brewfile): CLI tools, casks, fonts, Mac App Store apps, VS Code extensions
- **Git** — global config, gitignore, useful aliases
- **macOS** — [`macos/defaults.sh`](macos/defaults.sh), Dock layout plist, optional Hammerspoon center-window hotkey
- **Apps** — non-secret preference snapshots (Rectangle, Dato, Sublime, VS Code, Terminal, Velja, …)
- **Services** — Automator Quick Actions (open in editor, PDF helpers, …)
- **Agents** — public-safe rules, skills, commands, and agent definitions under [`agents/`](agents/)
- **Safety** — gitleaks pre-commit, app-pref audit, skill license audit, Brewfile drift audit
- **Maintenance** — [topgrade](config/topgrade.toml) config with Brewfile audit hook

## Quick start

### Fresh Mac

```bash
git clone https://github.com/t4sh/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
bash install.sh
```

`install.sh` installs Xcode CLI tools (if needed), Homebrew, symlinks, Brewfile packages, NVM/Node, app prefs, Automator services, optional macOS/Dock/SSH prompts, git hooks, and Terminal profiles (quits Terminal — expected once).

It does **not** run: `rules-audit`, `skills-audit`, `make dock` (unless you answer yes), `make default-apps`, `make doctor`, `make docs-audit`, or `make skills`. Those are documented manual follow-ups.

After bootstrap:

1. Sign into iCloud / App Store
2. Restore `~/.secrets/` from your encrypted vault (if you use one) → `make link`
3. Complete the manual steps printed at the end of `install.sh`

### Existing Mac (already has Homebrew)

```bash
git clone https://github.com/t4sh/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
make all
```

`make all` runs: `link` → `rules-audit` → `skills-audit` → `brew` → `services` → `restore-apps` → `dock` → `hooks` → `ssh-setup` → `macos` (interactive, last).

Manual targets (not in `all`): `terminal`, `default-apps`, `capture-default-apps`, `doctor`, `docs-audit`, `skills`.

```bash
make help   # full target list with descriptions
```

## Architecture

```text
symlinks.tsv          declarative manifest → scripts/link.sh
install.sh            one-time fresh-Mac bootstrap
Makefile              idempotent re-apply + audits + backup
Brewfile              all packages (brew / cask / mas / vscode)
apps.tsv              defaults-export app plists
~/.secrets/           local-only credentials (never in git)
```

Add a new symlink: one row in [`symlinks.tsv`](symlinks.tsv). No Stow/dotbot config to learn.

## Make targets

### Bootstrap

| Target | Purpose |
|--------|---------|
| `make all` | Main re-apply sequence (see above) |
| `make link` | Apply symlinks from `symlinks.tsv` |
| `make brew` | Install Brewfile packages |
| `make brew-check` | Quick install-state check |
| `make restore-apps` | Restore tracked app preference snapshots |
| `make services` | Install Automator workflows |
| `make macos` | Apply macOS defaults (interactive) |
| `make dock` | Restore Dock layout |
| `make terminal` | Import Terminal profiles (quits Terminal — run outside Terminal.app) |
| `make ssh-setup` | Generate/register GitHub SSH key via `gh` |
| `make hooks` | Install git hooks (gitleaks) |

### Policy & audits

| Target | Purpose |
|--------|---------|
| `make default-apps` | Apply repo default-app policy from `config/duti` (after `make brew`) |
| `make capture-default-apps` | Refresh `config/duti` when you change editor/URL handlers |
| `make doctor` | Read-only bootstrap preflight |
| `make docs-audit` | Typo check docs/scripts (`typos` from Brewfile) |
| `make brewfile-audit` | Strict Brewfile ↔ system drift check |
| `make rules-audit` | Agent rule includes in sync |
| `make skills-audit` | Skill redistribution/license gate |
| `make audit-apps` | Scan app snapshots for secrets |

### Backup & secrets

| Target | Purpose |
|--------|---------|
| `make backup` | Refresh repo-tracked app prefs, Dock, services, Brewfile |
| `make backup-canary` / `make restore-canary` | Canary Mail vault workflow |
| `make backup-shottr` / `make restore-shottr` | Shottr license prefs vault workflow |
| `make secrets-backup` | Snapshot `~/.secrets/` into encrypted sparseimage |
| `make secrets-mount` / `make secrets-pass` | Vault mount / password helper |

### Agents

| Target | Purpose |
|--------|---------|
| `make skills-manifest` | Regenerate `Skillsfile` from skill lockfile |
| `make skills` | Install global skills from manifest (needs Node + auth for some sources) |

## `dot` and `bin/j`

[`bin/dot`](bin/dot) is on PATH and dispatches to `scripts/` and `macos/`:

```bash
dot                    # list scripts
dot link               # → scripts/link.sh
dot doctor             # → scripts/doctor.sh
dot macos defaults     # → macos/defaults.sh
```

[`bin/j`](bin/j) opens a project directory in Cursor/VS Code (or prints the path):

```bash
j                      # fzf picker under ~/Projects
j my-app               # substring match
j --print my-app       # print path only
```

Shell helper `jcd` (in `zsh/lib/50-functions.zsh`) fuzzy-cds into `~/Projects`.

## Hammerspoon

[`hammerspoon/init.lua`](hammerspoon/init.lua) is symlinked to `~/.hammerspoon`. After `make brew`, open Hammerspoon once and grant Accessibility.

- **Hyper** (`⌘⌥⌃⇧`) + `c` — center focused window at 1440×900 (capped to visible monitor frame)

[Rectangle](https://rectangleapp.com/) remains the primary window manager; Hammerspoon is intentionally minimal.

## Default app policy

[`config/duti`](config/duti) declares which app opens which extension or URL scheme for the **same app set** in the Brewfile — repo policy, not a blind machine snapshot. Optional handlers (for example full Xcode.app) are skipped with a warning when the app is not installed; `make default-apps` still applies everything else.

1. Fresh Mac: `make brew` → `make default-apps`
2. Changed preferences on your reference Mac: `make capture-default-apps` → review diff → commit

HTTPS default-browser mapping is omitted (`duti` returns error -54 for direct `https` binding on tested macOS versions).

## Agents & skills

The [`agents/`](agents/) directory symlinks to `~/.agents` and wires into Claude Code (`~/.claude/`). It includes:

- `AGENTS.md` and rule files
- A large **public-redistributable** skills tree
- `Skillsfile` / `.skill-lock.json` for reproducible global skill installs

Non-redistributable or private skills must **not** be committed — `make skills-audit` enforces the license gate (also in `make all`).

Install global skills after bootstrap:

```bash
make skills    # needs gh auth for some private skill sources
```

## Secrets

Nothing secret lives in git. Canonical layout:

```text
~/.secrets/
├── ssh/              → ~/.ssh/* via symlinks.tsv
├── config/           → gh, moltbook consumers
└── apps/             → Raycast, Transmit, Shottr, Monokai, Canary, …
```

Vault workflow:

```bash
make secrets-backup
make secrets-mount
make secrets-pass     # copy vault password from Keychain
```

## Safety gates

| Gate | When |
|------|------|
| **gitleaks** | Pre-commit — blocks new secrets |
| **audit-app-prefs** | `make backup` and manual audit |
| **audit-skill-licenses** | `make skills-audit` / `make all` |
| **audit-brewfile** | `make brewfile-audit`, topgrade hook |
| **verify-idempotency** | Optional drift harness (see below) |

## Idempotency

Every `make` target is safe to re-run. For a stronger check that a second `make all` converges:

```bash
scripts/verify-idempotency.sh snapshot
make all
scripts/verify-idempotency.sh diff
```

Snapshots live under `/tmp/dotfiles-idempotency-$USER/`.

## Local customizations

Per-machine overrides without forking core files:

| File | Purpose |
|------|---------|
| `zsh/lib/99-local.zsh` | Shell aliases, PATH, secrets — **gitignored** |
| `~/.dotfiles-local/` | macOS identity cache, backup destination, etc. |

Create `~/.dotfiles/zsh/lib/99-local.zsh` for anything that must not be committed.

## Repo layout

| Path | Purpose |
|------|---------|
| [`Brewfile`](Brewfile) | All packages |
| [`symlinks.tsv`](symlinks.tsv) | Symlink manifest |
| [`zsh/`](zsh/) | Shell configuration |
| [`git/`](git/) | Git config and global ignore |
| [`starship/`](starship/) | Prompt themes |
| [`config/`](config/) | Tool configs, duti, EditorConfig, inputrc, topgrade, MCP |
| [`hammerspoon/`](hammerspoon/) | Minimal window helper |
| [`agents/`](agents/) | Agent rules, skills, commands |
| [`apps/`](apps/) | App preference snapshots |
| [`macos/`](macos/) | System defaults and Dock |
| [`services/`](services/) | Automator Quick Actions |
| [`scripts/`](scripts/) | Bootstrap, backup, restore, audit, vault |

## Forking & updating

```bash
# fork on GitHub, then:
git clone git@github.com:<you>/dotfiles.git ~/.dotfiles
cd ~/.dotfiles && bash install.sh

# later:
cd ~/.dotfiles && git pull && make all
```

Remove or replace: Brewfile entries, `config/duti` rows, `apps/` snapshots, and agent skills you don't need before treating this as production-ready on your Mac.

## Design influences

Inspired by patterns from the broader dotfiles ecosystem ([dotfiles.github.io](https://dotfiles.github.io), [awesome-dotfiles](https://github.com/webpro/awesome-dotfiles)) and repos including:

- [holman/dotfiles](https://github.com/holman/dotfiles) — topical layout, `bin/dot` dispatcher
- [mathiasbynens/dotfiles](https://github.com/mathiasbynens/dotfiles) — macOS defaults reference
- [nicksp/dotfiles](https://github.com/nicksp/dotfiles) — modern Mac + Homebrew + agents/skills peer
- [thoughtbot/dotfiles](https://github.com/thoughtbot/dotfiles) — disciplined symlink workflow (via rcm; this repo uses `symlinks.tsv` instead)

Deliberately **not** using: GNU Stow, dotbot, chezmoi, or yadm — preferring a thin manifest + Makefile over a dotfiles framework.

## Contributing

This is a personal dotfiles repo published for reference and forking. Issues and PRs that fix bugs or improve portability without breaking changes are welcome; large opinion changes (editors, defaults, app policy) are better handled in your own fork.
