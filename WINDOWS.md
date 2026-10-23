# Windows workflow

For fresh setup or adoption of existing configuration, follow [the agent setup runbook](docs/AGENT-SETUP.md) before [Setup](#setup). Existing setups require backup-status confirmation and an approved migration plan; real directories at managed link destinations must be reconciled before linking. The maintenance notes below apply after setup.

## Maintenance scope and diagnostics

Use `update-all -SkipSkills` for apps only, or `update-all -SkipApps` for skills.
Each stage reports elapsed seconds. Topgrade output is retained in
`%TEMP%/dotfiles-topgrade-*.log`; failures point to that run's log. Retry only the
named failing step instead of repeating all maintenance.
Feedback uses blue for progress, green for success, yellow for warnings or reboot
requests, and red for failures. Topgrade logs retain UTF-8 text without ANSI colors;
the caller's encoding and color environment are restored after the stage.
Codex's desktop-bundled CLI is maintained with the desktop app; Topgrade's
standalone Codex updater is disabled.

Hermes is excluded from Windows `update-all`, including Topgrade. Keep its runtime
updates deliberate and verify them separately; a successful runtime check does
not enable automatic updates. Other updates and Mac maintenance remain
independent. Installation, settings, source launch and taskbar repair remain
available.

For deliberate standalone testing, use `scripts/update-windows-hermes.ps1`.
It honors `HERMES_HOME`, resolves the official managed runtime or a legacy venv,
verifies the runtime before and after updating, and logs startup
failures with the OS error and exact executable path in
`%TEMP%/dotfiles-hermes-update-*.log`. After a successful update it repairs the
source shortcut and checks shared skills. See
[Hermes Windows setup](docs/hermes-preferences.md#windows-source-launcher-and-shared-skills).

Maintenance prepares gcloud's copied update Python only for Topgrade and restores
the caller's `CLOUDSDK_PYTHON` afterward. After Topgrade, VS Code and Cursor
extensions are reconciled with the declared versions. Skill refresh shows one
progress line per source; failures point to `%TEMP%/dotfiles-skills-*.log`.
Inventory and license diagnostics are in `%TEMP%/dotfiles-skills-checks.log`.
The wrapper passes npm's `--yes` before `skills` and closes stdin to prevent
a first-use CLI installation from waiting on a hidden confirmation.
Python discovery checks the physical executable and runs a bounded version probe.
Resolve an Application Control denial before reinstalling dependent uv tools.
Topgrade output is decoded as UTF-8.
Dry runs skip Python preparation, extension changes and skill refresh.

This checkout provides native Windows setup alongside the Mac bootstrap. The
Brewfile and agent tree are shared; Windows packages, links and templates have
separate manifests under `config/windows-*.tsv` and `apps/windows/`.

## Setup

Use a Git checkout, Windows Terminal, winget (Microsoft App Installer), and
standard PowerShell 7.4 or newer. On a machine without Git, install it first
(`winget install --id Git.Git -e`) so the clone below works. Developer Mode is
not required; links fall back to hardlinks and junctions. Store-packaged
PowerShell is excluded because its filesystem redirection can reach different
preference files. Windows PowerShell 5.1 is supported only as the bootstrap
bridge.

The scripts require a persistent RemoteSigned policy (existing Unrestricted or
Bypass also works). Set it explicitly before setup, then open a fresh console:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
Get-ExecutionPolicy -List
git clone https://github.com/t4sh/dotfiles.git "$HOME\.dotfiles"
cd "$HOME\.dotfiles"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Apply
```

Group Policy takes precedence; the scripts do not override it. Full setup rejects
ZIP extractions before changes. Bootstrap installs or upgrades the standard
PowerShell runtime and installs Git, uv, Volta and Make as needed. It then applies
package, link, hook, skill and preference stages. Review `config/windows-links.tsv`
before linking: existing destinations may be backed up and replaced.
Link checks and repair reject existing files hidden behind MSIX cache redirection.
If reported, open standard PowerShell directly from Windows Run or Explorer and
retry so the workflow reaches the actual configuration files.

App selection defaults to `all`, preserving full bootstrap behavior. Use
`-AppGroups 'development,utilities'` with `install.ps1` or `dot setup`, or
`make all APP_GROUPS=development,utilities`, to select optional groups. A named
selection includes `essentials`. `none` keeps the native CLI/runtime baseline
but defers app casks, Windows App Store counterparts, fonts and editor
extensions. `fonts` selects Brewfile fonts; `development` selects Brewfile editor
extensions. Every non-font cask has exactly one group in
`config/app-groups.tsv`; invalid, missing or stale mappings stop setup before
installation. Partial selections skip aggregate preference restore, preserving
settings for deferred apps. An explicit `dot restore-apps -Apply` still applies
its full template scope. Windows App Store counterparts are all-only; select
`all` with `-Only <package-id>` for a specific counterpart.

Bootstrap reports completed, failed and skipped stages with retry commands.
Run `dot setup-status -AppGroups 'development,utilities'` or
`make setup-status APP_GROUPS=development,utilities` for selected/deferred app
counts, package inventory and local link, hook, skill and preference checks.
The command installs no apps and does not restore preferences or accept WinGet
source agreements; WinGet may query configured sources during inventory.
PowerShell, managed Python and pinned Node are checked locally. Individual
uv/Volta tool versions, fonts, account sign-ins, paid activation, default-app
choices, secret recovery and GUI behavior remain manual verification.

Arc, Latest, Linear, LobeHub, Maccy, Nimbalyst, Tolaria and Upscayl are retired
from automatic Mac and Windows installation. Existing app settings are retained;
setup does not uninstall these apps.

## Retired Paseo setup

If this machine previously used Paseo, follow the explicit preview/apply steps in
[the retirement guide](docs/PASEO-RETIREMENT.md). Removing package/link manifest
rows and rerunning `dot path` does not remove old links or an existing User PATH
entry. The cleanup verifies link ownership and preserves saved data and custom
install locations; review those separately. Native cleanup acceptance is pending.

## Daily commands

Run from the checkout, or use `dot` after setup adds its directory to PATH:

| Command | Behavior |
|---|---|
| `bin\dot.cmd help` | List native commands |
| `bin\dot.cmd doctor -Strict` | Check runtime, policy and configured surfaces |
| `bin\dot.cmd packages-check` | Compare declared packages |
| `bin\dot.cmd packages -Apply` | Install declared package counterparts |
| `bin\dot.cmd setup-status` / `make setup-status` | Report selected and deferred apps with local setup checks |
| `bin\dot.cmd restore-apps` | Preview template restoration |
| `bin\dot.cmd restore-apps -Apply` | Merge shipped template settings; close affected apps first |
| `bin\dot.cmd default-apps -OpenSettings` | Open Settings to choose VLC for supported media types |
| `bin\dot.cmd default-apps -Check` | Verify the declared VLC file associations |
| `bin\dot.cmd backup -Apply` | Retain curated public app templates |
| `bin\dot.cmd upgrade` | Update apps, runtimes and skills |
| `bin\dot.cmd hermes -Apply` | Apply shared-skill paths and source launcher; close Hermes first |
| `bin\dot.cmd hermes-launcher -Check` | Verify Start → Hermes selects source launch |
| `make skills` | Verify checked-in skill metadata |

OpenCode CLI updates belong to the outer WinGet stage through `SST.opencode`.
Its duplicate Topgrade step is disabled: Topgrade 17.13 rejects the CLI's bare
version output before attempting an update. This does not disable WinGet updates
for the CLI or the separately declared OpenCode Desktop package.

Skill checks and refresh output use UTF-8 even in a legacy-code-page console;
the caller's encoding is restored afterward. Native failures remain failures.

Windows public preference files are **curated onboarding templates**. Backup and
preference Backup entry points intentionally skip live capture, even when called
directly. Check compares the two Mac-authored Zed surfaces only; other template
comparisons remain skipped. This is not a claim that every live preference matches
the templates. Restore applies only shipped settings; unshipped
extra-app surfaces are skipped. Personal dictionaries, extension inventories,
accounts, device names and host layouts should stay outside this checkout.

Zed settings and keymap come from `apps/zed/` on the Mac side. Windows restores
them and never writes them back into the repository; the obsolete Windows-authored
Zed snapshots are removed. The shared keymap uses `secondary-` for Cmd on macOS
and Ctrl on Windows.

`-Only tower` scopes the extended-app restore to shipped Tower templates. Public
backup still retains templates and never captures live Tower preferences.

Private app exports can be placed in `~/.secrets/apps/` and encrypted separately;
see [SECRETS-WINDOWS.md](SECRETS-WINDOWS.md). Mac `make backup` likewise retains its
curated editor/Dock templates. Dato's personal shared-time-zone plist is omitted;
its single display-format template is separate from full private Dato recovery.

### Editor restore readiness

Use `dot restore-apps -Only sublime -Apply` for Sublime, or `-Only vscode` /
`-Only cursor` for one of the other editors. VS Code and Cursor restore also
install the declared extensions with Windows replacements. Reviewed version pins
are checked by version; direct VSIX releases must match their declared SHA256.
For disposable editor validation, pass both `-RoamingRoot` and `-ExtensionsDir`
with `-Only vscode` or `-Only cursor`; this keeps extension installation isolated.

Sublime restore installs the shared default-syntax helper and checks declared
packages, selected theme/color resources and the MultiMarkdown syntax resource.
On a new installation, use Tools → Install Package Control, then let package
installation finish before running `dot restore-apps -Only sublime -Check`.
Strict doctor includes this resource check even though public preference drift
comparison is intentionally skipped. Resource presence does not establish that
plugins load or that a theme license is activated; verify those inside Sublime.

A repeat restore with nothing to change can run while Sublime is open. Changes
to managed files wait until it is closed. A failed or deferred Sublime stage
does not prevent the other restore stages from being attempted; the command
reports the combined failures at the end. Personal keybindings, snippets, tasks,
profiles and extension state are not part of the curated public templates.

### VLC file associations

`config/windows-vlc-associations.tsv` lists 37 media extensions supported by
VLC's Windows registration. `.ts` remains with Cursor; `.ogm` and `.ogv` remain
with Edge. IINA plugin packages and formats not advertised by VLC are excluded.

After installing VLC, run `dot default-apps -OpenSettings` or
`make default-apps`, then choose VLC for the listed extensions in Windows
Settings. Restore does not write protected `UserChoice` registry keys.
Run `dot default-apps -Check` or `make default-apps-check` to verify the result.
The checker reports differing choices and formats not advertised by the current
VLC installation. On Windows 11, when `AppDefaults` `HashVersion` is 1, the
active choice is `UserChoiceLatest\ProgId`; the older `UserChoice` remains as a
rollback value. The checker prefers that latest choice for hash version 1, uses
the legacy choice for older hash versions, then falls back to the latest or
registered association when no user choice exists. It reads associations only.
Full `dot restore-apps -Check` and strict doctor include this check; the Settings
selection remains a manual setup step.

### Deskflow

Install Deskflow with `dot packages -Apply -Only Deskflow.Deskflow`. Package
installation and upgrades select and pin the newest permitted three-part stable
WinGet release. Four-part continuous builds are excluded; unsigned stable
`1.27.0` is blocked by Smart App Control, so the selected release is currently
`1.26.0`. If an installed stable or continuous version is blocked, the package
workflow replaces it with the permitted release. Keep Windows security enabled.
Client identity, server address and other machine-specific Deskflow settings are
not part of the public templates.


## Candidate validation

Mac checks cannot establish native Windows readiness. In an isolated Windows
profile or disposable VM, check parser errors, launchers from a new console with
no temporary policy override, setup/doctor, and a second setup run. Verify that
restore preserves unrelated dummy preferences and that encrypted recovery works
with disposable keys and data. Do not run setup against your everyday profile
just to validate a candidate.

The public-owned fixture exercises direct and wrapper backup entry points with
isolated dummy preference roots and verifies that public templates remain intact:

```powershell
pwsh -NoProfile -File tests/test_public_windows.ps1
pwsh -NoProfile -File tests/test_public_windows_editors.ps1
pwsh -NoProfile -File tests/test_public_windows_maintenance.ps1
pwsh -NoProfile -File tests/test_public_windows_projection.ps1
pwsh -NoProfile -File tests/test_windows_skills_prompt.ps1
pwsh -NoProfile -File tests/test_windows_python_discovery.ps1
pwsh -NoProfile -File tests/test_windows_update_reporting.ps1
pwsh -NoProfile -File tests/test_public_windows_hermes.ps1
```

The PowerShell `port-info <port>` helper inspects connections. The misleading former
`free-port` name is removed when the profile reloads; it never terminated listeners.
