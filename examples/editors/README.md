# Portable editor examples

These original snippets and shortcuts contain no commands that execute a shell,
workspace paths, account data or personal dictionary. Merge into your own editor
configuration; retain a backup and check for shortcut conflicts first. No example
is copied into an editor automatically.

## Preference fragments

| Fragment | Apply to | Coverage |
| --- | --- | --- |
| [vscode-settings.json](vscode-settings.json) | VS Code and Cursor | Appearance, indentation, whitespace, wrapping, save behavior, search, terminal, Git confirmations and workspace trust |
| [vscode-language-settings.json](vscode-language-settings.json) | VS Code and Cursor | Built-in JSON/HTML/CSS formatters and import-update prompts; enable only when project style agrees |
| [vscode-telemetry-off.json](vscode-telemetry-off.json) | VS Code; check Cursor support separately | Disable VS Code core telemetry; extensions/providers can have separate controls |
| [vscode-agent-settings.json](vscode-agent-settings.json) | VS Code only | Disable blanket and terminal agent auto-approval |

Merge selected keys through **Preferences: Open User Settings (JSON)**; keep your
other settings and a backup. Nested language objects must be merged, not replaced.
The base uses spaces but retains tabs for Makefiles and Markdown hard-break
whitespace. Autosave, format-on-save and Git auto-fetch are off; Git sync and file
operations retain confirmations. No extension install or formatter executable is
bundled. The optional language fragment enables on-save formatting using built-in
formatter IDs; other language servers/formatters remain your project choice.

Cursor uses the shared editor keys, but its agent run modes are separate. Select
its confirmation-based run mode locally; this collection does not install a
Cursor permissions allowlist or assume VS Code chat keys control Cursor.
See [Cursor agent security](https://prod.cursor.com/docs/agent/security).
Existing extensions, local/workspace overrides and managed policies still apply.
The optional telemetry fragment controls VS Code core telemetry only; it does not
control Cursor account/privacy policy, extension telemetry or AI provider retention.
Accounts, model selection, tasks and MCP integrations are not changed. Remove the added keys or restore your backup to undo changes.

## VS Code and Cursor snippets

Open **Preferences: Configure User Snippets**, create a global `.code-snippets`
file, and merge [markdown.code-snippets](markdown.code-snippets). The `scope`
limits completion to Markdown. Type `meeting-note`, `verification-note` or
`comparison-table`, then select the snippet; Tab advances through fields.

Merge [vscode-keybindings.json](vscode-keybindings.json) into **Preferences: Open
Keyboard Shortcuts (JSON)**. In a Markdown editor, `Ctrl+K Ctrl+M` inserts the
meeting note and `Ctrl+K Ctrl+V` inserts the verification note by exact snippet
name. These are two-step Control chords on all platforms, including macOS.
Install the snippets before using these bindings. Resolve conflicts in the
shortcut UI; Cursor may have its own bindings or overrides.

## Zed

Merge the objects in [zed-keymap.json](zed-keymap.json) into your user keymap
array via **zed: open keymap**. In a full editor, `secondary-k secondary-w`
toggles soft wrap and `secondary-k secondary-l` toggles line numbers.
`secondary` means Command on macOS and Control on Windows/Linux. Check the keymap
editor for action validity and shortcut conflicts in your installed version.

## Sublime Text

Use **Tools → Developer → New Snippet**, replace its contents with
[verification-note.sublime-snippet](verification-note.sublime-snippet), and save
it under **Preferences → Browse Packages → User** with that filename. In a
Markdown buffer, type `verification-note` and press Tab. The same five evidence
fields are available without installing a package or shell integration.

## Checks and references

The JSON and XML parse offline, the VS Code bindings name included snippets, and
Zed action identifiers match upstream defaults. Actual application dispatch and
GUI import remain unrun. Remove the merged objects/snippet to undo these changes.

Sources: [VS Code snippets](https://code.visualstudio.com/docs/editing/userdefinedsnippets),
[VS Code shortcuts](https://code.visualstudio.com/docs/configure/keybindings),
[Zed keymaps](https://zed.dev/docs/key-bindings),
[Zed action identifiers](https://github.com/zed-industries/zed/blob/main/assets/keymaps/default-macos.json),
[Sublime snippets](https://www.sublimetext.com/docs/completions.html#snippets).

Preference references: [VS Code settings](https://code.visualstudio.com/docs/configure/settings), [workspace trust](https://code.visualstudio.com/docs/editing/workspaces/workspace-trust), [agent approvals](https://code.visualstudio.com/docs/agents/run/approvals). Checked 2026-10-10; live application loading and permission enforcement remain unrun.
