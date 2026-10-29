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
| Secrets | `*.local` files | `~/.secrets/` + encrypted recovery DMG (`make secrets-backup`) |
| Verification | Uncommon | `make doctor`, `brewfile-audit`, `verify-idempotency.sh`, gitleaks |
| AI agents | Emerging (e.g. nicksp) | Whole [`agents/`](agents/) tree, skills lockfile, license gate |

**Scope:** macOS, plus native Windows setup in [WINDOWS.md](WINDOWS.md). No chezmoi/yadm templating — per-machine overrides go in gitignored `zsh/lib/99-local.zsh`.

## Optional app groups and setup status

The Brewfile remains the package inventory. `config/app-groups.tsv` assigns
each non-font cask to one group; fonts are derived from `font-*` casks and VS
Code extensions belong to `development`. Windows uses the same groups through
its existing package mappings. Missing, duplicate or stale group rows fail
validation before app installation.

```bash
make app-groups                              # list groups and declaration counts
make brew-apps APP_GROUPS=essentials          # primary browser and daily utilities
make brew-apps APP_GROUPS=design,ai           # essentials plus design and AI apps
make brew-apps APP_GROUPS=development,fonts   # essentials, editors/extensions and fonts
APP_GROUPS=essentials bash install.sh         # fresh Mac with a smaller app selection
make setup-status APP_GROUPS=essentials      # inspect that selection; never apply fixes
dot setup-status --groups essentials         # same report outside the repo directory
```

Groups: `essentials`, `development`, `design`, `ai`, `media`, `browsers`
(additional browsers), `productivity`, `utilities`, and `fonts`. Named selections
also include essentials. `all` and `none` must be used alone. The default remains
`all` for compatibility. Selections apply to the current invocation only; pass
the same selection when checking or retrying. Adding a group never uninstalls
apps or deletes settings. Formulae, runtime tools and the separate App Store
phase retain their existing behavior.

For a partial selection, `install.sh` and `make all` defer the aggregate app
preference restore, keeping existing app settings. `make restore-apps` remains
an explicit full restore. Other bootstrap stages, including configuration links,
portable agent hooks and optional macOS/Dock policy, retain their existing scope;
use `make brew-apps` to install a group without running those stages.

`make setup-status` reads local package inventories and runs existing checks for
selected packages, links, services, hooks, the skill manifest, macOS policy and
saved preferences. Missing tools and timeouts are reported as unknown; failures
do not prevent the remaining checks. The report lists next commands and exits
nonzero when review is needed. Saved-preference checks cover all snapshots,
including apps outside a partial selection; drift is reported for review and is
never repaired. App Store/vendor sign-ins, GUI permissions, activation and vault
recoverability remain manual checks. The status command performs no installs,
restores or sign-in or authentication checks. Temporary inspection
files may be created and removed by the existing checks.

The bootstrap completion report separates finished phases, failed phases with
retry commands, deferred choices and manual work. It also reports an early
failure without implying that the rest of setup completed. `make verify-bootstrap`
remains the strict post-vault gate for the **full** declared inventory; optional
group selection does not weaken it. Windows equivalents are in [WINDOWS.md](WINDOWS.md).

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

Using an AI agent? Point it at [AGENTS.md](AGENTS.md); its [setup runbook](docs/AGENT-SETUP.md) covers fresh setup and adoption of existing configuration. For existing setups, confirm backup status or explicit consent to migrate an unorganized setup without a backup, and approve the migration plan before changes. Start with the [fork setup guide](docs/FORKING.md) to set your identity, signing key, and local SSH configuration before bootstrap. A [generic SSH example](ssh/config.example) is included for adaptation.

### Fresh Mac

```bash
git clone https://github.com/t4sh/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
bash install.sh
```

Use `~/.dotfiles` after resolving any existing occupant through the [migration checkpoint](docs/AGENT-SETUP.md#adopt-an-existing-setup). A custom location requires separate adaptation and verification: `DOTFILES` alone does not update shell and runtime paths that still reference `~/.dotfiles`.

`install.sh` installs Xcode CLI tools (if needed), Homebrew, **brew-core** then resumable **brew-apps**, pinned Node via `make node`, npm globals via `make brew-npm`, shims, convergent Automator services, app prefs, optional Dock, git hooks, optional macOS defaults (including Touch ID sudo) last, and optionally Terminal profiles at the very end.

Shared automated steps match `make all`: services → restore-apps → dock → hooks → macos. Pre-vault `make link` warns and skips missing `~/.secrets` sources (exit 0 unless `DOTFILES_STRICT_LINK=1`); after vault restore, `make post-vault` performs the strict relink and SSH/app recovery.

It does **not** run: `rules-audit`, `skills-audit`, `make dock` / `make macos` (unless you answer yes), `make post-vault`, `make default-apps`, `make doctor`, `make docs-audit`, or `make skills`. Those are documented manual follow-ups.

After bootstrap:

1. Sign into the App Store, then run `make brew-mas`.
2. Mount the vault, run `make secrets-restore` → `make secrets-restore-apply` → `make secrets-pass-import` (never rsync a snapshot onto `/`).
3. Recover the tool Keychain items listed by `make keychain-list`, run `make keychain-check`, and authenticate with `gh auth login -h github.com`. Then run `make post-vault`: it prepares legacy shell settings, strictly links required consumers and restores independent apps. Missing authentication or Keychain items remain pending and return a nonzero status.
4. Finish the GUI leftovers list from `post-vault`, then run `make verify-bootstrap`.

### Existing Mac (already has Homebrew)

Before cloning or running `make all`, follow the [existing-setup migration checkpoint](docs/AGENT-SETUP.md#adopt-an-existing-setup). Resolve any existing `~/.dotfiles` checkout and agree which settings to retain, merge or replace. `make all` applies the full policy; use selected targets for a partial adoption.

```bash
git clone https://github.com/t4sh/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
make all
```

`make all` runs serially (including under `make -j all`): `link` → `rules-audit` → `skills-audit` → `brew-without-mas` → `shims` → `skills-engine` → `skills-browser` → `services` → `restore-apps` → `dock` → `hooks` → `macos` (interactive + Touch ID sudo, last). App Store apps stay explicit via `make brew-mas`.

`make brew` runs `brew-base` → `node` → `brew-npm`, then optional/interactive MAS. Fresh re-apply prefers `brew-without-mas`.

The npm phase enables pnpm/Yarn shims after installing Corepack. Re-run it after changing the dotfiles Node pin. Other project-specific NVM installations need their own `corepack enable`; projects still select package-manager versions through `packageManager`.

`ssh-setup` is deliberately manual and restore-first: it validates and registers an existing vault-backed key. Creating a new canonical identity requires the explicit `scripts/ssh-setup.sh --generate` option.

Manual targets (not in `all`): `post-vault`, `ssh-setup`, `terminal`, `default-apps`, `doctor`, `verify-bootstrap`, `docs-audit`, `skills` / `skills-update`.

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
| `make brew` | Phased install with optional MAS confirmation |
| `make brew-without-mas` | `brew-base` → `node` → `brew-npm` (used by `make all`) |
| `make brew-core` / `make brew-apps` | Bootstrap formulae, then resumable casks/fonts/extensions |
| `make brew-base` | Aggregate of `brew-core` → `brew-apps` |
| `make node` | Install/activate the exact runtime from `.node-version` |
| `make brew-npm` | Install pinned-Node npm globals and enable Corepack shims |
| `make brew-mas` | Install App Store apps after signing in |
| `make brew-check` | Quick install-state check (`scripts/brewfile.sh check`) |
| `make shims` | Create or repair the pinned `node-stable` / `npx-stable` shims |
| `make restore-apps` | Restore tracked app prefs (running-app gate quits/reopens managed apps) |
| `make services` / `make services-check` | Install Automator workflows / compare installed copies with the repo |
| `make macos` | Apply macOS defaults + Touch ID sudo (`sudo_local`) |
| `make macos-check` | Verify managed appearance, Control Center, battery, Dock, and input policy |
| `make touch-id-sudo` | Idempotently enable Touch ID for sudo |
| `make verify-bootstrap` | Strict post-vault gate for rules, skills, app snapshots, links, services, hooks, macOS policy, and default apps |
| `make dock` | Restore Dock layout |
| `make terminal` | Import Terminal profiles (quits Terminal — run outside Terminal.app) |
| `make ssh-setup` | Validate/register a restored GitHub SSH key via `gh` |
| `make hooks` / `make hooks-check` | Install tracked git hooks / verify hook routing and executable bits |

### Policy & audits

| Target | Purpose |
|--------|---------|
| `make default-apps` | Apply repo default-app policy from `config/duti` (after `make brew`) |
| `make default-apps-check` | Compare live Launch Services handlers with `config/duti` |
| `make capture-default-apps` | Refresh `config/duti` when you change editor/URL handlers |
| `make doctor` | Read-only bootstrap preflight (Touch ID, duti receipt, managed Automator workflows, vault note) |
| `make docs-audit` | Typo check docs/scripts (`typos` from Brewfile) |
| `make brewfile-audit` | Strict Brewfile ↔ system drift check |
| `make rules-audit` | Agent rule loading, routing and inventory in sync |
| `make skills-audit` | Skill redistribution/license gate |
| `make audit-apps` | Scan app snapshots for secrets |

### Backup & secrets

| Target | Purpose |
|--------|---------|
| `make backup` | Refresh portable snapshots and reviewed Brewfile changes; back up Text Replacements into `~/.secrets/` |
| `make backup-text-replacements` | Export Mac Text Replacements into the secrets tree |
| `make backup-canary` / `make restore-canary` | Canary Mail vault workflow (restore quits/reopens Canary) |
| `make backup-shottr` / `make restore-shottr` | Shottr license prefs vault workflow (restore quits/reopens Shottr) |
| `make secrets-backup` | Update the encrypted DMG with capacity-based retention and verified snapshots of `~/.secrets/` |
| `make secrets-backup-portable` | Create a separate immutable recovery DMG |
| `make secrets-mount` / `make secrets-pass` | Vault mount / local password-copy helper |
| `make secrets-restore` / `secrets-restore-apply` | Validate / transactionally restore only `~/.secrets` |
| `make secrets-health` | Mounted-vault snapshot freshness check |
| `make secrets-pass-import` | Import a recovered vault password into the local Keychain |

`make backup` keeps the public macOS policy check strict. It does not capture a
personal policy JSON. Brewfile additions and removals need interactive review;
`make backup OVERRIDE=1` keeps the generated Brewfile after validation. The
Services and device-domain rows in `apps.tsv` have no published snapshots yet,
so public backup leaves them uncaptured pending separate privacy review.

### Agents

| Target | Purpose |
|--------|---------|
| `make skills-manifest` | Regenerate `Skillsfile` from skill lockfile |
| `make skills` | Verify vendored skills and manifest without a network install |

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

## Automatic RTK for Mac agents

Brewfile installs RTK. `make restore-codex-rtk restore-claude-rtk` resolves its
executable from `PATH` and merges an automatic command-rewrite hook into each
client's local configuration, preserving other hooks and settings. Both targets
run in `install.sh` and `make all`; `make codex-rtk-check claude-rtk-check` verifies
the definitions and runs in `make verify-bootstrap`. Re-run restore after moving RTK.

Reload Codex and review/trust **RTK command compression** in Hooks (CLI `/hooks`).
Trust remains local to each machine. Claude Code loads its hook after restarting.
The previous dotfiles-owned Codex hooks symlink migrates to a local file.

`make restore-claude-settings` merges the saved Claude Code attribution keys from
[`config/claude/settings.json`](config/claude/settings.json) (empty commit/PR
attribution, `includeCoAuthoredBy: false`) into `~/.claude/settings.json`, leaving
every other key to Claude Code. It runs in `install.sh` and `make all`;
`make claude-settings-check` runs in `make verify-bootstrap`.
No personal configuration, command history, credentials, or RTK statistics are
captured by these targets. The portable implementation is [scripts/rtk-hook.py](scripts/rtk-hook.py).

Run ordinary shell commands normally; supported ones are rewritten through RTK.
Use `rtk proxy <command>` for exact output, full file reads, or machine-readable
results. Existing approval and sandbox checks still apply. This setup targets Mac;
Windows integration remains separate.

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

The media policy includes explicit IINA handlers. IINA's Screengrabs folder
follows the macOS screenshot policy during restore, backup, and drift checks;
a fresh checkout uses `~/Desktop/Screengrabs`. See the
[IINA backup guide](apps/iina/README.md) for path overrides and plugin coverage.
On Windows, use `dot default-apps -OpenSettings` and `dot default-apps -Check`
for the supported VLC media types; see [Windows file associations](WINDOWS.md#vlc-file-associations).

HTTPS default-browser mapping is omitted (`duti` returns error -54 for direct `https` binding on tested macOS versions).

## Preference coverage

Preference coverage is selective: capture portable, non-secret settings; keep credentials and licensed exports in the encrypted vault; leave account-bound or machine-specific state to vendor sync or manual setup.

- **App snapshots:** `make restore-apps` restores `apps.tsv` and documented irregular settings; `make apps-drift` checks only faithful snapshots this public projection ships.
- **Stable backups:** equivalent plist captures retain their previous bytes after both copies are sanitized. Encoding, key order, and volatile bookkeeping do not cause churn; real preference and ordered-list changes still update snapshots. Curated editor and Dock templates remain portable.
- **macOS policy:** `make macos` applies automatic appearance, hot corners, battery percentage, and visibility for Bluetooth, Clock, Focus, Sound, and Wi-Fi; `make macos-check` verifies the managed values.
- **Dock:** `make dock` imports a full-domain, public-safe snapshot; where the snapshot overlaps `macos/defaults.sh`, scripted policy is authoritative.
- **Keyboard and input sources:** the managed policy includes key repeat, keyboard navigation and Globe-key action; the input-source plist is captured separately. Services preferences have no published snapshot and public backup skips them. Restore restarts the current user's `cfprefsd`, verifies portable managed values, and reports an explicit logout fallback if either step cannot be confirmed.
- **Text Replacements:** `make backup-text-replacements` writes an importable plist to `~/.secrets/`; see [restore steps](macos/TEXT-REPLACEMENTS.md).
- **Cursor CLI:** the two attribution flags are restored selectively from [`apps/cursor/cli-config.json`](apps/cursor/cli-config.json) without replacing other CLI settings. Use `make restore-cursor-cli` and `make cursor-cli-check`.
- **Zed:** one Mac-authored settings/keymap pair is also restore-only on Windows; Windows backup does not capture it.
- **Tower:** when installed, app restore imports GitHub’s public GPG verification key for web merge signatures.
- **Manual or vendor-managed:** wallpaper and custom images, display layout, network profiles, volume, Screen Time, notification schedules, and unlisted Control Center modules remain outside the tracked policy.

## Agents & skills

The [`agents/`](agents/) directory symlinks to `~/.agents`, wires into Claude Code (`~/.claude/`), exposes canonical skills at `~/.cursor/skills`, and installs a Codex bootstrap bridge at `~/.codex/AGENTS.md`. It includes:

- `AGENTS.md` and rule files
- A large **vendored skills** tree with upstream attribution in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)
- `Skillsfile` / `.skill-lock.json` for reproducible global skill installs

Non-redistributable or private skills must **not** be published — `make skills-audit` enforces the license gate (also in `make all`). Third-party skills without a local `LICENSE` file must appear in `THIRD_PARTY_NOTICES.md`.

Install global skills after bootstrap:

```bash
make skills           # verify checked-in skills
make skills-update    # explicit upstream refresh; may need GitHub auth
make skills-engine  # Install/verify Impeccable's pinned engine; downloads if missing
make skills-engine-check # Read-only Impeccable engine readiness check
make skills-browser # Install Fluid Functionalism audit dependencies without lifecycle scripts
make skills-browser-check # Read-only browser dependency loading check
```

On Mac, `make skills-update`, `make all`, and full bootstrap also install and
verify Impeccable's pinned engine through its checksum-verifying launcher.
Doctor checks it offline; repair a missing engine with `make skills-engine`.
`make skills` remains an offline inventory check, not proof of runtime readiness.
The same Mac setup and refresh commands install Fluid Functionalism's audit
dependencies with lifecycle scripts disabled. Doctor checks that Playwright can
load; repair it with `make skills-browser`. Actual audits also need Chrome or a
compatible Chromium, and a running page to measure.

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

Vault workflow (details and recovery limitations in [SECRETS.md](SECRETS.md)):

```bash
make secrets-backup   # requires a separately stored, verified recovery copy
make secrets-mount
make secrets-pass     # copy the local Keychain password without printing it
make secrets-pass-import  # import a recovered password on a replacement Mac
```

`make secrets-pass-import` uses the native Keychain password prompt so the
recovered password stays out of process arguments. `make secrets-pass` schedules
a best-effort clipboard clear after 30 seconds when its pasteboard generation is
unchanged. Clipboard history and cross-device copies are outside that timer.

The CLI-created Keychain item is local and is not assumed to synchronize through iCloud Keychain. Store and verify a separate recovery copy in an independently synchronized password manager. Before attach, vault scripts detect the selected image at any mountpoint, reuse only the verified expected mount, and never claim an operator-owned alternate attachment. Backups stage through a working copy, retain the published vault on failure, and retain verified snapshots while reserving space for two more and preserving baselines. Portable and legacy backup commands remain available; see [SECRETS.md](SECRETS.md).

### On-demand credentials and recovery (Mac)

Keep all active environment files in `~/.secrets/config/env/` (directory mode `700`,
files mode `600`). `~/.secrets/env.sh` is a compatibility symlink to `shell.env`;
`make link` / `make post-vault` recreates it when the target exists. For a new setup,
copy `zsh/secrets.example` to `config/env/shell.env` inside the secrets tree first.
`post-vault` also prepares it automatically: an older regular `env.sh` is preserved
in the private link recovery archive without activating its code or old global
tokens. Review that archive locally and restore only non-secret shell settings.
When a legacy regular file and an existing canonical file coexist, recovery stops
for local reconciliation even if their contents match; neither file is overwritten.
Only the generated safe shell stub permits an automatic retry. Review both files,
preserve the legacy file in the private recovery archive, and retain only non-secret
settings in the canonical file before rerunning `make post-vault`. The legacy file stays untouched until linking succeeds. Missing required sources stop linking.
Displaced secret-backed consumer files go to private
`~/.secrets/recovery/link-backups/` rather than the ordinary dotfiles backup tree.
The old `~/.secrets/env/` directory is retired. Recovery archives under
`~/.secrets/recovery/` are vault-backed and never loaded automatically.

After mounting the vault: `make secrets-restore` validates the selected payload and `make secrets-restore-apply` transactionally replaces only `~/.secrets`; then run `make secrets-pass-import` and **`make post-vault`** as the single consumer-link/SSH/app follow-on.

**Keychain-first credentials (Mac):** environment files contain non-secret settings
and references such as `export TYPESAFE_API_KEY='keychain://dotfiles/typesafe/TYPESAFE_API_KEY'`.
Use Keychain Access to create or update a **generic password** with that service
name (the part after `keychain://`) and your macOS login username as the account.
Put the credential in its password field. Keychain controls access prompts; the
loaders never answer dialogs or unlock the keychain automatically. These local
Keychain items are not included in `make secrets-backup`; do not assume they sync
to another Mac. Restore/recreate them separately before testing restored loaders.
Run `make keychain-list` for the profile/variable/service inventory.
`config/keychain-profiles.tsv` is a fork-owned requirement list. Uncomment or add
only the tools you use; once listed, a missing profile cannot silently pass an
empty inventory. The public template intentionally requires no personal services. Intentional file-only
backups are excluded from that list. Use your macOS
login username as the account for each generic password. `make keychain-check`
checks metadata only; it never requests passwords or proves API validity. Both
`post-vault` and doctor report missing items; independent app restores continue
while missing credentials remain recorded as pending recovery work.
Older portable installations can still use literal file values; migrated profiles
contain references only, with no plaintext fallback on Keychain denial.

Shared shell startup loads no migrated credentials and performs no Keychain
lookups. `shell.env` is reserved for non-secret shell settings; interactive zsh
unsets `GH_TOKEN` and `GITHUB_TOKEN` so stale inherited tokens cannot override
`gh`'s stored credentials. For other tools, create a named profile and use the generic runner.
Use `~/.dotfiles/bin/tool-env exa -- COMMAND [ARG...]` or `tool-env exa --check`.
Each profile is read from `~/.secrets/config/env/PROFILE.env` and only that profile's
credentials are resolved for the child command. Profile syntax is literal env
assignments; shell commands and substitutions are not executed.

For consumers with a literal env-file loader, use
`tool-env --adapter NAME -- COMMAND [ARG...]` or `tool-env --adapter NAME --check`.
`config/tool-env-adapters.tsv` maps each adapter name to its env-file override,
profile suffix, loader path, and required variables. Loader paths are relative to
the dotfiles root or absolute. `TOOL_ENV_ADAPTERS` selects another mapping file.
The existing `tool-env PROFILE ...` commands do not read the adapter mappings.
For a profile named `--adapter`, the existing `--check` and `-- COMMAND` forms
take precedence over adapter selection.

Adapter mode follows the configured env-file override, then
`${XDG_CONFIG_HOME:-$HOME/.config}/env/$(whoami).SUFFIX.env`, then the first
matching `*.SUFFIX.env`. It resolves Keychain references into a temporary profile
with permissions `600` inside a directory with permissions `700`, sets the
override, and sources the configured loader before launching your command.
The profile remains available if the loader is sourced again and is removed on
exit or handled interruption. Keep tracing disabled in credential-consuming commands.
`--check` resolves the profile and runs the loader without launching your command.
The loader must parse the temporary assignments as literal data, never source
the profile directly as shell code. Duplicate keys and multiline credentials
are rejected; existing file-backed values and optional empty settings are supported.

Explicitly designated backup credential files may retain plaintext values under
`~/.secrets/config/env/` with mode `600`, alongside the Keychain copies. Keep those
files out of Git and include them in the encrypted vault backup; do not automatically
convert an intentional backup copy into references.

**Context7 (Mac):** `~/.secrets/config/env/context7.env` holds the
`CONTEXT7_API_KEY` reference to `dotfiles/context7/CONTEXT7_API_KEY`. After restoring
the vault, Keychain items, and app preferences, run `make context7`. It merges the
local launcher into Cursor's global `~/.cursor/mcp.json`, Zed's
`~/.config/zed/settings.json`, VS Code's default user-profile `mcp.json`, and
Claude Code's user-scope `mcpServers` in `~/.claude.json`.
Other settings, servers, comments, and existing VS Code credential-input records
are preserved. Named VS Code profiles, `CLAUDE_CONFIG_DIR` overrides, and
project-level overrides are separate. Claude Code rewrites `~/.claude.json` while
running; if setup reports a concurrent change, rerun it.
Re-run after restoring Zed preferences, which intentionally exclude MCP configuration.
`make context7-check` verifies Keychain access, runtime, and wiring; it does not
make an API call or prove editor activation. Restart the Context7 server after
rotating its Keychain value. The pinned server receives the key at startup, not
per tool call. Codex's connected Context7 app is managed separately.

**Claude Code MCP (Mac):** `make claude-mcp` adds user-scope Paper
(`~/.paper/bin/paper mcp`), brilliant (`http://127.0.0.1:3333/mcp`, live only while
the app runs) and GitHub (`api.githubcopilot.com/mcp/`) entries to `~/.claude.json`,
matching Codex and Zed. GitHub's header comes from `bin/github-mcp-headers`, which
reads `gh auth token` at connect time; no token is stored in settings. Run
`gh auth login` first. `make claude-mcp-check` verifies the token is present and the
wiring is current; it makes no API call. Restart Claude Code sessions to load them.

**Figma REST API (Mac):** `~/.secrets/config/env/figma.env` holds the `FIGMA_TOKEN`
reference to `dotfiles/figma/FIGMA_TOKEN`. `~/.dotfiles/bin/figma-env --init` creates
a private reference file without replacing an existing path. Prefix API commands
with `~/.dotfiles/bin/figma-env --` to retrieve the token for that command and its
children. `make figma-check` checks Keychain readiness; `make figma-api-check`
makes one read-only `/v1/me` request, showing only status, never token or account
data. That probe needs `current_user:read`. On renewal, update the Keychain item's
password and rerun both checks. No shell/editor restart is needed for this runner.

**Figma MCP and Paper use different authentication:** the official Figma remote
MCP uses client-managed account sign-in at `https://mcp.figma.com/mcp`. The REST
token above does not replace that sign-in. If using the Figma Cursor plugin, it owns
its MCP configuration; keep OAuth credentials in the client, outside dotfiles.
After restoring/installing the plugin, use its Authenticate action as needed.
See [Figma's setup guide](https://developers.figma.com/docs/figma-mcp-server/remote-server-installation/).

Paper's local MCP uses its desktop CLI rather than a separate API key. Install
Paper Desktop and configure the absolute `~/.paper/bin/paper` path with argument
`mcp` in your client's stdio MCP configuration, or use the supported client plugin.
Keep credentials and client account state outside this repository. Read-only
canvas checks require Paper Desktop running with a file open. See
[Paper's client setup guide](https://paper.design/docs/mcp).

**TypeSafe / Jev (Mac):** run `~/.dotfiles/bin/typesafe-env --init` once to create
`~/.secrets/config/env/typesafe.env` with a reference to
`dotfiles/typesafe/TYPESAFE_API_KEY`. Store the key in that Keychain item as above.
Initialization preserves existing paths. Run `~/.dotfiles/bin/typesafe-env --check`
to verify access without displaying the key. Prefix SDK/API commands with
`~/.dotfiles/bin/typesafe-env --` to retrieve only the TypeSafe key for that command
and its children. Missing/empty credentials or denied access stop execution.
Ordinary chats, skill loading, and shell startup do not retrieve it. The wrapped
command receives the key, so keep environment dumps and credential logging off.

Run `make agent-clients-check` for instruction-bridge placement; see
[`agents/CLIENTS.md`](agents/CLIENTS.md) for account setup and runtime verification.

## Git hooks

On macOS, Git 2.54+ also runs `git/global-hooks/commit-msg` through the additive
`hook.strip-cursor-trailers` registration. `make link` points that directory at
`~/.config/git/hooks`. The filter removes Cursor attribution from a final
trailer block and preserves normal message prose and other trailers. It does
not replace `core.hooksPath`: Git still runs repository hooks, including custom
hook directories, and runs their `commit-msg` hook after the filter. Older Git
keeps its existing hooks and does not run this filter. For a repository opt-out,
set `git config --local hook.strip-cursor-trailers.enabled false`. `--no-verify`
bypasses the filter too. Ambiguous blocks and multiline attribution values stay
unchanged.

`git config core.hooksPath .githooks` wires the tracked `.githooks/` directory
(`make hooks`, part of `make all`). The per-clone `git/hooks/` path stays unused.

## Safety gates

| Gate | When |
|------|------|
| **gitleaks** | Pre-commit — blocks new secrets |
| **audit-app-prefs** | `make backup` and manual audit |
| **audit-skill-licenses** | `make skills-audit` / `make all` |
| **audit-brewfile** | `make brewfile-audit`, topgrade hook |
| **verify-idempotency** | Optional drift harness (see below) |

Hosted CI runs gitleaks plus macOS-native shell syntax, rule/skill inventory, and executable Impeccable fixtures. A separate manual workflow exercises the real core `install.sh` path on a disposable `macos-15` runner while deliberately excluding GUI casks, app preference restore, Dock, system defaults, MAS, and vault recovery.

## Idempotency

Every `make` target is safe to re-run. This is load-bearing — bootstrap is meant as "apply current state," not "run once."

Notable contracts:

- **`make brew-without-mas` / `make brew`** — phased core/apps/node/npm with MAS deferred or optional (npm never lands under Homebrew's transient Node).
- **`make restore-apps`** — running-app gate derives apps from `apps.tsv` plus irregular settings surfaces, fails closed when process state is unknown, quits managed apps, restores, and reopens what it quit. The hosting editor is never quit; ambiguous Code-family identity skips Cursor/VS Code prefs while continuing. Override with `DOTFILES_RESTORE_FORCE=1`. Same lifecycle for `restore-shottr` / `restore-canary`.
- **`make apps-drift`** — compares live state only with faithful snapshots this public projection ships; intentionally excluded snapshots have no manifest rows, and curated VS Code/Cursor onboarding templates are outside the live-drift contract.
- **`make link`** — missing `~/.secrets` sources warn and skip (strict mode: `DOTFILES_STRICT_LINK=1`).
- **`make unlink`** — removes only managed symlinks; it does not automatically restore originals. Review timestamped backups under `~/.dotfiles-backup/`, or `~/.secrets/recovery/link-backups/` for secret-backed consumers, and select what to restore manually.

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

Shell fragments load in filename order: completion initialization precedes zoxide, and `99-syntax-highlighting.zsh` loads highlighting after plugins and `99-local.zsh`, so local editor widgets exist first.

## Repo layout

| Path | Purpose |
|------|---------|
| [`Brewfile`](Brewfile) | All packages |
| [`symlinks.tsv`](symlinks.tsv) | Symlink manifest |
| [`zsh/`](zsh/) | Shell configuration |
| [`git/`](git/) | Git config and global ignore |
| [`starship/`](starship/) | Prompt themes |
| [`config/`](config/) | Tool configs, duti, EditorConfig, inputrc, topgrade |
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

## Windows

See [WINDOWS.md](WINDOWS.md) for native setup and maintenance, and [SECRETS-WINDOWS.md](SECRETS-WINDOWS.md) for encrypted backups. Windows snapshots are curated onboarding templates: backup and drift commands preserve them rather than importing your live personal settings.

Hermes preference backup is user-owned and excluded from this public repository. See [Hermes preferences](docs/hermes-preferences.md) for restoring settings and disabling Desktop message reactions.

Checkout-safe regression fixtures: `make test-public` on macOS; `pwsh -NoProfile -File tests/test_public_windows_maintenance.ps1` on a bootstrapped Windows checkout. Fixtures do not replace fresh-machine or GUI verification.

## Daily shell maintenance

| Command | Purpose |
| --- | --- |
| `ls-recent` | Detailed listing, newest first |
| `view-reset` | Apply Finder/Open–Save policy and limited layout reset |
| `ds-clean` | Recursive `.DS_Store` cleanup from the current directory |
| `logs-check` / `logs-clean` | Preview/delete old user logs |
| `up-brew` / `re-brew` | Upgrade packages / upgrade plus maintenance |
| `dock-lock` / `dock-unlock` | Lock/unlock Dock settings |
| `dock-gap`, `dock-gap-small`, `dock-gap-files`, `dock-gap-files-small` | Add Dock spacers |
| `colima-up` / `colima-down` / `colima-status` | Manage Colima |
| `dot-link` / `dot-backup` | Link configuration / capture managed snapshots |
| `pr-digest <org>` / `pr-merged` | PR summaries / local tips matching merged PRs |
| `port-info [port ...]` / `port-reset [--force] <port> ...` | Group TCP listeners by preview, macOS and other processes / free ports |

Historical names remain compatibility aliases except `free-port`, which is removed.
`logs-clean` does not restart services; the script's explicit `--reset-services` option does.

### Finder policy

`view-reset` uses Columns, Date Modified groups, Name sorting within groups, previews,
hidden items and 13-point text. Home and existing `/Applications`, `/System/Applications`,
and `~/Applications` use List view with Name ascending. Set **Group By → None** manually
for those exceptions; the native check verifies only view and sorting.

Daily metadata discovery uses an optional `~/FileVault` directory and its directory
symlink targets, with one child level below each root. It does not scrub all folders.
Use `--root <directory>` and `--depth <levels>` for an explicit scope, or `--dry-run`
to preview. Cloud target discovery, validation, directory reads and backups have
30-second deadlines; the paused deletion phase has a separate total deadline.
Originals are backed up outside Git when metadata files are selected for deletion.
Home metadata and Applications trees are protected. Finder may recreate metadata after relaunch.

`ds-clean` is separate: no depth limit, timeout or backup; it preserves Home metadata
and Applications trees and does not follow symlinks. Starting it from Home can traverse
cloud storage for a long time. Run `view-reset` afterward to reapply preferences.

`make macos` applies the shared policy with `--policy-only`, without metadata scrubbing.
`make macos-check` checks global preferences; `view-reset --check-folders` verifies
exceptions through Finder in a GUI session. Backup preflight skips daily view-policy drift.
Native Open/Save Columns/Date Modified defaults are fallbacks; apps may override them,
and native panels do not support Finder-style grouping. Reopen existing dialogs.

On an existing Mac, run `make macos` and `make default-apps` to reapply the saved
Finder/Open–Save and handler policies, then run `make macos-check`,
`view-reset --check-folders`, and `make default-apps-check` to read them back.
If this public checkout uses a personal screenshot folder, set `DOTFILES_CAPTURE_DIR`
for `make macos-check`; the unset policy uses the portable Desktop fallback.

Privacy reviewers and fork users: read the [intentional public identity baseline](PRIVACY.md).
The documented noreply Git identity and public verification key are deliberately published.

Optional [portable config and editor examples](examples/README.md), [Services/device policy fixtures](examples/macos/README.md), and [public verification keys](docs/PUBLIC-KEYS.md) are available for manual adaptation.
