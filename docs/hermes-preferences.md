# Hermes preferences

Personal Hermes settings and model choices are not shipped in this public checkout.
`apps/hermes/` is ignored. Keep backups outside Git; the generic helper accepts
explicit `--live` and `--snapshot` paths for capture, check and restore. Stop Hermes
sessions before restoring. Use an initialized Hermes Python environment when the
live file is YAML. Capture requires an existing `model.default` and excludes auth
fields; review the result before sharing it.

```sh
python3 scripts/hermes-settings.py capture --live "$HOME/.hermes/config.yaml" --snapshot "$HOME/.dotfiles-local/hermes-preferences.json"
python3 scripts/hermes-settings.py restore --live "$HOME/.hermes/config.yaml" --snapshot "$HOME/.dotfiles-local/hermes-preferences.json"
```

On Windows, pass the active profile's config path explicitly; the default is under
`HERMES_HOME` when set, otherwise `%LOCALAPPDATA%/hermes`. Shared-skill preferences
can be managed separately with `--skills-only`; restoration adds shared discovery
without removing existing profile-specific directories. This public checkout does
not install a Hermes profile or apply a personal model policy.

## Disable Desktop message reactions

Set `display.message_reactions` to `false` in your own saved preferences. The helper
preserves that boolean, but the Desktop appearance setting has separate browser
storage and can overwrite the backend value when reconnecting.

In Hermes Desktop, select the default/local backend and open **Settings → Appearance
→ Message Reactions**. Turn it off, reconnect, and verify it remains off. Double-click
a message and confirm no heart reaction or reaction feedback occurs. Repeat after
restarting Desktop. This setting concerns message reactions; completion and prompt
bells are separate preferences. Backend restoration alone does not verify the GUI.

## Windows source launcher and shared skills

After initializing Hermes, `dot hermes -Apply` adds `~/.agents/skills` to skill
creation and discovery, preserving other skill directories and personal settings.
It also configures Start → Hermes for source launch. Close Desktop, CLI and gateway
sessions before applying preferences; the command reports busy processes without
stopping them. `dot hermes -Check` verifies the settings and runtime skill inventory.
Setup skips an uninitialized Hermes installation.

Existing profiles with skill-directory links into the shared collection must first
follow the isolation procedure below. The settings helper refuses to restore
preferences while those links are present.

Use `dot hermes-launcher -Apply` to repair just the shortcut, or `-Check` to inspect
it. Both launcher commands honor `HERMES_HOME`; explicit `-HermesHome`,
`-HermesRoot` and `-Python` select a profile and runtime. `dot hermes -Apply`
passes the selected Python through to the shortcut. The shortcut invokes that
Python with `desktop --source --skip-build`.
Launching does not install, update, package or rebuild anything. Source dependencies
and compiled frontend assets must already be present in the installed checkout.
The first replaced shortcut is retained as `Hermes.lnk.before-dotfiles`.

The shortcut owns Desktop's `com.nousresearch.hermes` Windows app identity.
Setup and successful updates back up and retire conflicting shortcuts targeting
this installation's Electron/Hermes executable, avoiding the bare Electron welcome
screen. The check also detects competing app identities. Unrelated shortcuts
remain untouched; a conflicting identity owned by another installation stops
repair before changes. Repeated repairs retain previous shortcut backups.
Existing Hermes taskbar pins are separate shortcuts: setup repairs their launch
command and icon in place, preserving each original beside it. The check includes
pinned shortcuts; unrelated pins and pin ordering remain unchanged. No new pins
are created. The bundled `assets/icon.ico` is preferred, so source-only installs
need no packaged executable for the icon. Missing icon assets fail clearly.
Missing identity on an owned pin is repaired; conflicting identities stop before
writes. Unreadable unrelated shortcuts are reported and skipped.

The dedicated update stage runs the native Hermes updater once, repairs the source
shortcut after success, then checks shared skills. The native updater controls
checkout/dependency changes and can rebuild Desktop; this wrapper does not alter
that upstream behavior. Keeping the source shortcut avoids selecting a newly
packaged executable that Windows may block. If open Hermes processes lock runtime
files, the updater may fail: its exit status and log are retained. Resolve the
reported busy process before retrying that stage. There is no automatic process
termination or retry loop.

Personal models, aliases, appearance and credentials remain outside this checkout.
The generic helper now includes `display.resume_last_session`. For an explicit
user-owned snapshot, `--preserve-model-selection` on full restore/check preserves
the current provider, endpoint and model while merging saved aliases and other
managed preferences. It cannot be combined with capture or `--skills-only`.
Desktop theme, scale and other renderer settings still require manual restoration.

## Keep bundled categories out of shared skills

Hermes uses its profile-local `skills/` directory for bundled and hub content.
Use `skills.external_dirs` to discover `~/.agents/skills`, and `skills.create_dir`
for deliberate creation of shared skills. Do not link profile-local skill
directories into the shared collection: bundled category sync follows directory
symlinks and Windows junctions and can write metadata into their targets.

The generated `Skillsfile` selects `--agent codex` once on both operating systems.
The Windows installer wrapper passes it through and adds npm consent, closed
stdin and logging. Keep that selector on manual `skills add` commands too;
unscoped installs can recreate Hermes-local links. Existing client links and
Hermes external discovery provide access to the canonical collection.

With Hermes stopped and shared external discovery already configured, run from
this checkout on Mac:

```sh
python3 scripts/hermes-settings.py isolate-skills
python3 scripts/hermes-settings.py check-skills
```

On Windows, select the initialized profile and its Python explicitly:

```powershell
$hermesProfile = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $env:LOCALAPPDATA 'hermes' }
$hermesPython = Join-Path $hermesProfile 'hermes-agent/venv/Scripts/python.exe'
& $hermesPython -B scripts/hermes-settings.py isolate-skills --live (Join-Path $hermesProfile 'config.yaml')
if ($LASTEXITCODE -ne 0) { throw 'Skill isolation failed; inspect the reported condition.' }
& $hermesPython -B scripts/hermes-settings.py check-skills --live (Join-Path $hermesProfile 'config.yaml')
if ($LASTEXITCODE -ne 0) { throw 'Skill boundary check failed.' }
```

For a custom runtime, substitute its Python path. For another Mac profile, pass
its config with `--live`; the Mac default intentionally ignores `HERMES_HOME`.

Isolation moves only matching alias objects into the profile's
`skill-alias-backups/`; shared targets and real Hermes directories are retained.
Repeated runs are safe. Existing backup conflicts, aliased profile roots and
unreadable directories fail clearly. Relative links may be dangling in backup;
moving them back would restore the unsafe boundary.

Capture, restore and check reject shared aliases before preference writes.
This is a settings guard, not a patch to Hermes: direct Hermes operations and
deliberate shared-skill edits still have their normal permissions.
The shared `research/DESCRIPTION.md` path is also gitignored to prevent accidental
staging. Ignoring does not prevent writes, and existing files need provenance
review before relocation or removal.

Public fixtures cover isolation, idempotency, unchanged targets, later local
category writes and failure preservation. The migration fixture uses a real
junction when run on Windows. Mac fixture verification does not establish native
Windows acceptance; run the Windows fixtures before relying on that platform's
runtime behavior.
