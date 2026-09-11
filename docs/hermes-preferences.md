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
