# Optional portable examples

These are original, hand-authored examples, not exports of a live account or
machine. Bootstrap, backup and restore do not install them. Review the fragment,
back up the destination, and merge only the settings you choose. Remove those
settings or restore your backup to undo the change.

| Example | Use | Platforms |
| --- | --- | --- |
| [Codex preferences](codex/README.md) | Permissions, output, environment, history and TUI | Supported Codex hosts; enforcement depends on host policy |
| [Hermes preferences](hermes/README.md) | Display, compression, limits, skills and optional memory/backend | Mac, Windows, Linux with Hermes installed |
| [Zed preferences](zed/README.md) | Appearance, editing, trust and language tooling | Mac, Windows, Linux |
| [VS Code/Cursor and snippets](editors/README.md) | Editor preferences, Markdown notes and editing shortcuts | Mac, Windows, Linux |
| [Services and trackpad policies](macos/README.md) | Minimal preference fixtures; review in System Settings | macOS only |

## Agent and editor preference collections

- [Codex](codex/README.md): permissions, shell environment, output, history,
  TUI preferences, read-only/edit profiles and generic project guidance.
- [Hermes](hermes/README.md): display/session, compression, limits, approvals,
  skills, optional memory and Docker execution, and generic assistant guidance.
- [Zed](zed/README.md): appearance, editing, save/trust behavior and language tooling.
- [VS Code/Cursor](editors/README.md): shared editor baseline, language formatting,
  VS Code-only agent approvals, plus snippets and keymaps.

Fragments are independently selectable. Examples avoid accounts, personal model
aliases, project trust lists, live memory, remote inventories, credentials and
private rulebook content. Platform/client-specific settings are labelled; a VS
Code agent setting does not establish Cursor's permission policy.

## Verification

JSON, snippet XML, TOML and plist syntax were checked offline. Settings and editor
actions were checked against upstream documentation/source on 2026-10-10. These
checks do not certify authentication, GUI shortcut dispatch, live preference
application or native Windows behavior. See [public verification keys](../docs/PUBLIC-KEYS.md)
for key purposes and the publication boundary.
