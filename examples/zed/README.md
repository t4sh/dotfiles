# Generic Zed preferences

Merge selected keys from [settings.json](settings.json) through **zed: open
settings**. Back up your current settings; do not replace the whole file. This
example is original, contains no live account state and is not installed by Make.

It covers built-in light/dark themes, font sizes, keymap, save behavior, indentation,
wrapping, whitespace, brackets, terminal appearance and Markdown/Make exceptions.
Worktree trust remains enabled, automatic prediction display is off, and buffers are not
silently restored across restarts. Autosave and formatting are off in the base.

The Make override requires the [Make extension](https://zed.dev/docs/languages/makefile);
it does not install the extension automatically.

The optional [language-settings.json](language-settings.json) enables language
servers and selected on-save formatting. Trusted projects can start language
servers; availability depends on installed extensions/tooling. Review formatting
against the project's own style before enabling it. No custom executable, remote
server, account/provider or model is configured. For shortcuts, use the existing
[Zed keymap](../editors/zed-keymap.json) and check conflicts in your installed version.

The optional [telemetry-off.json](telemetry-off.json) disables Zed diagnostic and
metric reporting; it does not control third-party tools or a model provider.

Remove the merged keys or restore your backup to undo these choices. References:
[Zed settings](https://zed.dev/docs/reference/all-settings),
[appearance](https://zed.dev/docs/appearance) and
[worktree trust](https://zed.dev/docs/worktree-trust), checked 2026-10-10. JSON syntax
and documented settings were checked; actual GUI dispatch, language server startup
and native Windows behavior remain unrun.
