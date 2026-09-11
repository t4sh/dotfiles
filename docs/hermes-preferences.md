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
