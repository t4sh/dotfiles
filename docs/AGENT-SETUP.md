# Agent setup runbook

Read this before an agent sets up a fresh Mac or Windows machine, or adopts this
repository on a machine with existing configuration. It orders the existing human
guides and marks what an agent must not do alone. The checkout encodes one person's
policy: treat every step as a proposal for the machine owner, not a default to apply.

## Before any change

1. Confirm whose machine and identity this is, and whether it is fresh, already
   managed by dotfiles, or has scattered configuration. For either existing-setup
   case, complete the planning and approval checkpoint in
   [Adopt an existing setup](#adopt-an-existing-setup) before cloning into an
   occupied path, editing configuration or running setup.
   If it is not the repository owner's machine, follow [FORKING.md](FORKING.md)
   after that checkpoint: set Git identity and signing
   in `git/gitconfig` before any linking step. Linking installs that file as the
   user's global Git configuration.
2. Show the owner what linking replaces and get approval. `symlinks.tsv` (Mac)
   and `config/windows-links.tsv` (Windows) replace user-level files, including
   shell, Git and agent configuration: `~/.agents`, `~/.claude/CLAUDE.md`,
   `~/.claude/skills` and `~/.codex/AGENTS.md` on both, plus Cursor, Copilot and
   Gemini rules on Mac. Existing Mac files move to
   `~/.dotfiles-backup/<timestamp>/` (secret-backed ones under
   `~/.secrets/recovery/link-backups/`); existing Windows files are kept beside
   the target as `<name>.backup-<id>`. Windows preserves existing real directories
   and refuses to replace them; reconcile those first as described below. These
   recovery copies cover replaced paths, not a complete backup of the existing
   setup. Remove rows the owner does not want before linking.
3. Ask before each opinionated stage: `Brewfile` app casks and Mac App Store
   apps (`make brew-apps`, `make brew-mas`), Dock layout (`make dock`), macOS
   defaults and Touch ID sudo (`make macos`), default apps (`make default-apps`),
   Windows packages (`config/windows-packages.tsv`) and app preferences.
4. Never create keys or credentials unprompted. Do not run
   `scripts/ssh-setup.sh --generate`, `gh auth login`, or vault restores on the
   owner's behalf; hand those to the owner.

## Adopt an existing setup

1. Inspect without changing files. Identify any existing `~/.dotfiles` checkout,
   its remote, local changes and linked consumers; inspect the actual targets of
   links as well as ordinary files. Identify another configuration manager, shell
   and Git settings, agent instructions and custom skills, app preferences, and
   credential locations. Report locations and conflicts without exposing secrets.
2. Show a migration plan: what stays, what will be merged into the fork, and what
   will be replaced. Keep credentials outside Git. An occupied `~/.dotfiles` is
   not a clone destination: reuse it only if it is the intended fork and its local
   work is preserved. Otherwise agree a relocation with the owner before using
   that path; leave the old checkout and its linked consumers intact until then.
3. Ask the owner to confirm backup status before any migration writes. Proceed
   only when they confirm either that the existing setup and linked source files
   are backed up, or that the setup was unorganized and they explicitly accept
   migrating the reviewed scope without a backup. If neither is confirmed, pause
   for the owner to arrange their own backup or decide how to proceed. This
   runbook does not require the agent to create a backup; automatic link recovery
   copies do not satisfy this checkpoint. Record the owner's decision and scope.
4. Plan directory reconciliation before linking. On Windows, real directories at
   `~/.agents`, `~/.claude/skills` or other managed destinations are preserved and
   cause a link failure. On Mac, whole-directory replacement also requires review
   of custom contents. Agree what to retain or merge and obtain approval for any
   relocation, or omit the unwanted manifest rows. Do not delete directories or
   substitute copies for links to make setup pass. Preserve applicable existing
   agent instructions and reconcile conflicting policy with the owner.
5. Obtain approval for the concrete migration plan and selected stages before
   applying any planned merges, relocations or replacements. Existing approval
   for that same scope need not be requested again. Review Mac link
   actions with `bash scripts/link.sh --dry-run`; after Windows prerequisites are
   available, use `bin\dot.cmd link -Check` to identify conflicts. A failing check
   reports work to reconcile, not permission to replace it. The `install.ps1`
   preview is a stage summary, not an inventory of existing destination conflicts.
   Run only the approved stages; `make all` and full bootstrap apply broad policy.
6. Verify the selected configuration and reload the adopted agent instructions.
   Report retained settings, migrated paths, deferred stages and unresolved
   diagnostics. An approved partial adoption need not match every upstream
   default; report its limits rather than applying more policy to clear warnings.

## Updating a setup that previously used Paseo

Removing a manifest row does not remove an existing consumer link or Windows
PATH entry. After the existing-setup approval checkpoint, follow
[Paseo retirement](PASEO-RETIREMENT.md) to preview and explicitly apply the narrow
cleanup. It preserves custom directories, foreign links, other PATH entries and
saved app data. Review a custom app installation separately.

## Mac

1. Prerequisites the owner completes: Xcode Command Line Tools (a GUI prompt) and
   an administrator password for Homebrew, `chsh` and sudo-backed defaults.
2. Use `~/.dotfiles` for the fork checkout after resolving any existing occupant
   through the migration checkpoint. Complete [FORKING.md](FORKING.md). Setting
   `DOTFILES` alone does not support another location end to end: shell modules
   and runtime lookup still reference `~/.dotfiles`. A custom location requires
   separate adaptation and verification before linking.
3. Hand `bash install.sh` to the owner to run in their own terminal. It prompts
   with `read` for Dock, macOS defaults and Terminal profiles, so a
   non-interactive agent shell stops partway. On a machine that already has
   Homebrew, `make all` is the non-bootstrap path; it still ends in interactive
   `make macos`.
4. Without the repository owner's encrypted vault, skip `make secrets-*`,
   `make keychain-*` and `make post-vault`. A pre-vault `make link` warns about
   missing `~/.secrets` sources and continues.
5. Verify with `make doctor` (read-only). `make verify-bootstrap` passes only
   after the vault and `make post-vault` steps in the fresh-Mac section of
   [README.md](../README.md).

## Windows

1. Prerequisites the owner completes: Windows Terminal, winget, Git
   (`winget install --id Git.Git -e`) and the CurrentUser `RemoteSigned`
   execution policy from the setup section of [WINDOWS.md](../WINDOWS.md).
   Developer Mode is not required: file links fall back to hardlinks and
   folders use junctions. Some winget packages raise UAC prompts; the owner
   approves those or reruns the named package elevated.
2. Use `$HOME\.dotfiles` for the Git checkout (ZIP extracts are rejected), after
   resolving any existing occupant through the migration checkpoint. Complete
   [FORKING.md](FORKING.md) and reconcile real-directory conflicts before linking.
3. Run `install.ps1` without `-Apply` first; it previews and changes nothing.
   Show the preview to the owner, then run the `-Apply` command from
   [WINDOWS.md](../WINDOWS.md) after approval.
4. Verify with `dot doctor -Strict`. Account sign-in, manual packages and secrets
   recovery remain the owner's steps.

## Agent rules

Follow applicable existing user/global instructions alongside this repository's
`AGENTS.md` throughout setup. Installing the fork does not authorize discarding
the owner's current rules. Reconcile conflicting policy before replacing its
instruction source. After approved linking creates or updates `~/.agents` (Mac
`make link`; Windows link stage), reload the adopted rulebook with its documented
loader and verify the intended client instruction paths. Report what ran, what
was skipped for the owner, and the verification result; an unverified step is not
complete.
