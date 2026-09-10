# Editor readiness

## Mac commands

- `make restore-zed`: restore only the saved Zed settings/keymap, using the
  existing quit/refuse/reopen gate. Run outside Zed's integrated terminal.
- `make zed-check`: verify managed settings, keymap, declared extension directories
  and selected theme resources after launching Zed. Extra local agent options do
  not mask differences in managed keys. Authentication is checked in the editor.
- `make cursor-extensions`: install Prettier while retaining the public Cursor
  template's built-in theme.
- `make vscode-extensions`: install and pin Shell Format 7.2.5 through VS Code's
  marketplace. The brew app/base targets run this after the Brewfile installer.

Shell Format 7.2.8's JavaScript references `dist/one_ini_bg.wasm`, but the
published extension omits that asset. The extension can appear installed while
its formatter cannot activate. This is an upstream package defect, not a
Windows/Mac configuration difference. Use the complete prior release rather
than inserting an untracked binary into an installed extension.
[Upstream issue 396](https://github.com/foxundermoon/vs-shell-format/issues/396).

Installing the explicit version marks it pinned in VS Code. Revisit the pin only
after inspecting a newer package and successfully formatting a disposable shell
file in the actual editor. Brewfile inventory alone cannot prove activation.
Windows already selects 7.2.5 in `config/windows-extensions.tsv`; Cursor's
Windows source is the author's checksum-verified VSIX because its catalog did
not offer that version. Mac Cursor's deliberately smaller set does not include
Shell Format.

Zed uses its own language services and formatters; VS Code's Shell Format
extension does not provide anything to Zed. Its native agent, Inline Assistant,
and edit predictions also have different authentication from ACP external agents.
Open the project directory for language-service testing, not just a loose file.
Zed's Nginx extension additionally requires `nginx-language-server` on PATH.
It is declared as a uv tool in Brewfile and the Windows package mapping;
repair an existing Mac with `uv tool install nginx-language-server`.

Sublime's Package Control snapshot is normalized during backup and drift staging:
package names are unique and alphabetically sorted, and other settings are
preserved. Live files remain owned by Sublime. Thaw and Battery Indicator remain
Mac snapshots; Windows has no corresponding app-preference restore.
