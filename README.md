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
| App prefs | mackup or manual | [`apps.tsv`](apps.tsv) + `make backup` / `make restore-apps`; convergent Sublime managed files; licensed prefs in vault |
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
- **macOS** — [`macos/defaults.sh`](macos/defaults.sh), Dock layout plist, Hammerspoon window management
- **Apps** — non-secret preference snapshots (Dato, Sublime, VS Code, Cursor, Terminal, Velja, Rectangle fallback prefs, …)
- **Services** — Automator Quick Actions (open in editor, PDF helpers, …)
- **Agents** — public-safe rules, skills, commands, and agent definitions under [`agents/`](agents/), with client projection ownership in [`agents/CLIENTS.md`](agents/CLIENTS.md)
- **Safety** — gitleaks pre-commit, app-pref privacy and live-drift audits, skill license audit, Brewfile drift audit
- **Maintenance** — [topgrade](config/topgrade.toml) config with Brewfile audit hook

## Quick start

### Fresh Mac

```bash
git clone https://github.com/t4sh/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
bash install.sh
```

`install.sh` resolves the repo root from its own location (or `DOTFILES` if set), so a non-default clone path works: `DOTFILES=~/src/dotfiles bash ~/src/dotfiles/install.sh`.

`install.sh` installs Xcode CLI tools (if needed), Homebrew, Brewfile **base** packages (excluding npm + App Store), pinned Node via `make node`, npm globals via `make brew-npm`, shims, convergent Automator services, app prefs, optional Dock, git hooks, optional macOS defaults last, and optionally Terminal profiles at the very end.

Shared automated steps match `make all`: services → restore-apps → dock → hooks → macos. Pre-vault `make link` warns and skips missing `~/.secrets` sources (exit 0 unless `DOTFILES_STRICT_LINK=1`); re-run `make link` after vault restore.

It does **not** run: `rules-audit`, `skills-audit`, `make dock` / `make macos` (unless you answer yes), `make post-vault`, `make default-apps`, `make doctor`, `make docs-audit`, or `make skills`. Those are documented manual follow-ups.

After bootstrap:

1. Sign into the App Store, then run `make brew-mas`.
2. Sign into iCloud if needed, recover the vault password from an independent password manager, restore `~/.secrets/`, then run `make secrets-pass-import`.
3. Run `make post-vault` only after the existing secret-backed identity is restored. It installs the default backup manifest if absent, strictly links every declared consumer, verifies/registers the GitHub key, and restores vault-backed app preferences when present.
4. Complete the remaining manual steps printed by `install.sh` (Canary/Shottr restore quits/reopens those apps automatically).

### Existing Mac (already has Homebrew)

```bash
git clone https://github.com/t4sh/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
make all
```

`make all` runs serially (including under `make -j all`): `link` → `rules-audit` → `skills-audit` → `brew` → `shims` → `services` → `restore-apps` → `dock` → `hooks` → `macos` (interactive, last).

`make brew` itself is phased: `brew-base` → `node` → `brew-npm` → `brew-mas`.

`ssh-setup` is deliberately manual and restore-first: it validates and registers an existing vault-backed key. Creating a new canonical identity requires the explicit `scripts/ssh-setup.sh --generate` option.

Manual targets (not in `all`): `ssh-setup`, `terminal`, `default-apps`, `capture-default-apps`, `doctor`, `docs-audit`, `skills`.

```bash
make help   # full target list with descriptions
```

## Architecture

```text
symlinks.tsv          declarative manifest → scripts/link.sh
install.sh            one-time fresh-Mac bootstrap
Makefile              idempotent re-apply + audits + backup
Brewfile              all packages (brew / cask / mas / vscode / npm)
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
| `make brew` | Phased install: `brew-base` → `node` → `brew-npm` → `brew-mas` |
| `make brew-base` | Install Brewfile except npm and App Store entries |
| `make node` | Install/activate the exact runtime from `.node-version` |
| `make brew-npm` | Install Brewfile npm globals under that pinned Node |
| `make brew-mas` | Install App Store apps after signing in |
| `make brew-check` | Quick install-state check (`scripts/brewfile.sh check`) |
| `make shims` | Create or repair the pinned `node-stable` / `npx-stable` shims |
| `make restore-apps` | Restore tracked app prefs (running-app gate quits/reopens managed apps) |
| `make services` | Install Automator workflows |
| `make macos` | Apply macOS defaults (interactive) |
| `make dock` | Restore Dock layout |
| `make terminal` | Import Terminal profiles (quits Terminal — run outside Terminal.app) |
| `make ssh-setup` | Validate/register a restored GitHub SSH key via `gh` |
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
| `make backup-canary` / `make restore-canary` | Canary Mail vault workflow (restore quits/reopens Canary) |
| `make backup-shottr` / `make restore-shottr` | Shottr license prefs vault workflow (restore quits/reopens Shottr) |
| `make secrets-backup` | Snapshot `~/.secrets/` into encrypted sparseimage |
| `make secrets-mount` / `make secrets-pass` | Vault mount / local password-copy helper |
| `make secrets-pass-import` | Import a recovered vault password into the local Keychain |

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

[`hammerspoon/init.lua`](hammerspoon/init.lua) is symlinked to `~/.hammerspoon` by `make link`. After `make brew`:

1. Open Hammerspoon and enable **Launch Hammerspoon at login**.
2. Enable Hammerspoon in **System Settings → Privacy & Security → Accessibility**.
3. Run `make doctor` to verify the config link, runtime, and permission.

Window management:

- `⌃⌥Return` → almost maximize (90%, centered)
- `⌃⌥⇧Return` → maximize
- `⌃⌥Delete` → restore the pre-Hammerspoon frame
- `⌃⌥C` → center without changing size
- `⌃⌥-` / `⌃⌥=` → make smaller / bigger in 30 px steps
- `⌃⌥⌘←` / `⌃⌥⌘→` → previous / next display
- Hyper (`⌘⌥⌃⇧`) + `C` → center at `1440x900` px, capped to the monitor frame
- Drag a window title bar to a display's top edge → preview and almost maximize

Hammerspoon is the primary window manager. [Rectangle](https://rectangleapp.com/) remains installed as a manually launched fallback (`launchOnLogin` disabled in the tracked prefs).

## Default app policy

[`config/duti`](config/duti) declares which app opens which extension or URL scheme for the **same app set** in the Brewfile — repo policy, not a blind machine snapshot. Optional handlers (for example full Xcode.app) are skipped with a warning when the app is not installed; `make default-apps` still applies everything else.

1. Fresh Mac: `make brew` → `make default-apps`
2. Changed preferences on your reference Mac: `make capture-default-apps` → review diff → commit

HTTPS default-browser mapping is omitted (`duti` returns error -54 for direct `https` binding on tested macOS versions).

## Agents & skills

The [`agents/`](agents/) directory symlinks to `~/.agents`, wires into Claude Code (`~/.claude/`), exposes canonical skills at `~/.cursor/skills`, and installs a Codex bootstrap bridge at `~/.codex/AGENTS.md`. It includes:

- `AGENTS.md` and rule files
- A large **vendored skills** tree with upstream attribution in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)
- `Skillsfile` / `.skill-lock.json` for reproducible global skill installs

Non-redistributable or private skills must **not** be committed — `make skills-audit` enforces the license gate (also in `make all`). Third-party skills without a local `LICENSE` file must appear in `THIRD_PARTY_NOTICES.md`.

Install global skills after bootstrap:

```bash
make skills    # needs gh auth for GitHub-authenticated skill sources
```

## Secrets

Nothing secret lives in git. `~/.secrets/` is the single canonical tree; tools read auth through consumer symlinks in `symlinks.tsv`.

```text
~/.secrets/
├── ssh/              → ~/.ssh/* via symlinks.tsv
├── config/           → gh consumers
└── apps/
    ├── canary-mail/  # realms + plist — make backup-canary / restore-canary
    ├── shottr/       # license prefs — make backup-shottr / restore-shottr
    ├── raycast/      # manual import
    ├── transmit/     # manual import
    ├── sublime-text/ # Monokai license (optional)
    └── vscode/       # token-bearing MCP/profile data — manual restore
```

Vault workflow:

```bash
make secrets-backup   # requires a separately stored, verified recovery copy
make secrets-mount
make secrets-pass     # copy the local Keychain password without printing it
make secrets-pass-import  # import a recovered password on a replacement Mac
```

The CLI-created Keychain item is local and is not assumed to synchronize through iCloud Keychain. Store and verify a separate recovery copy in an independently synchronized password manager. Before attach, vault scripts detect the selected image at any mountpoint, reuse only the verified expected mount, and never claim an operator-owned alternate attachment. Backups stage through hidden partial directories, retain complete snapshots on copy failure, and prune only finalized snapshots.

## Safety gates

| Gate | When |
|------|------|
| **gitleaks** | Pre-commit — blocks new secrets |
| **audit-app-prefs** | `make backup` and manual audit |
| **audit-skill-licenses** | `make skills-audit` / `make all` |
| **audit-brewfile** | `make brewfile-audit`, topgrade hook |
| **verify-idempotency** | Optional drift harness (see below) |

## Idempotency

Every `make` target is safe to re-run. This is load-bearing — bootstrap is meant as "apply current state," not "run once."

Notable contracts:

- **`make brew`** — phased `brew-base` → `node` → `brew-npm` → `brew-mas` (npm never lands under Homebrew's transient Node).
- **`make restore-apps`** — running-app gate derives apps from `apps.tsv` plus irregular settings surfaces, fails closed when process state is unknown, quits managed apps, restores, and reopens what it quit. The hosting editor is never quit; ambiguous Code-family identity skips Cursor/VS Code prefs while continuing. Override with `DOTFILES_RESTORE_FORCE=1`. Same lifecycle for `restore-shottr` / `restore-canary`.
- **`make apps-drift`** — compares live state only with faithful snapshots this public projection ships; intentionally excluded snapshots have no manifest rows, and curated VS Code/Cursor onboarding templates are outside the live-drift contract.
- **`make link`** — missing `~/.secrets` sources warn and skip (strict mode: `DOTFILES_STRICT_LINK=1`).

For a stronger check that a second `make all` converges:

```bash
scripts/verify-idempotency.sh snapshot
make all
scripts/verify-idempotency.sh diff
```

Snapshots live under `/tmp/dotfiles-idempotency-$USER/`. The verifier normalizes only documented macOS runtime-noise keys; every remaining link, repository, Brewfile, preference, or defaults difference is actionable and returns nonzero.

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
| [`hammerspoon/`](hammerspoon/) | Primary window manager (Rectangle-style shortcuts + top-edge Almost Maximize) |
| [`agents/`](agents/) | Agent rules, skills, commands |
| [`apps/`](apps/) | App preference snapshots |
| [`macos/`](macos/) | System defaults and Dock |
| [`services/`](services/) | Automator Quick Actions |
| [`scripts/`](scripts/) | Bootstrap, backup, restore, audit, vault |

## License

This repository is [MIT licensed](LICENSE). Vendored agent skills retain their upstream licenses — see [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

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
