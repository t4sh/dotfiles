# Windows workflow
## Maintenance scope and diagnostics

Use `update-all -SkipSkills` for apps only, or `update-all -SkipApps` for skills.
Each stage reports elapsed seconds. Topgrade output is retained in
`%TEMP%/dotfiles-topgrade-*.log`; failures point to that run's log. Retry only the
named failing step instead of repeating all maintenance.
Codex's desktop-bundled CLI is maintained with the desktop app; Topgrade's
standalone Codex updater is disabled. Hermes is updated once using
`scripts/update-windows-hermes.ps1`, through its native Python runtime.
It uses `HERMES_HOME` or `%LOCALAPPDATA%/hermes`, skips an absent installation,
and rejects incomplete or hidden MSIX-redirected installations. Its output is
retained in `%TEMP%/dotfiles-hermes-update-*.log`. After a successful update, the
source shortcut is repaired and shared skills are checked. See
[Hermes Windows setup](docs/hermes-preferences.md#windows-source-launcher-and-shared-skills).

Maintenance prepares gcloud's copied update Python only for Topgrade and restores
the caller's `CLOUDSDK_PYTHON` afterward. After Topgrade, VS Code and Cursor
extensions are reconciled with the declared versions. Skill refresh shows one
progress line per source; failures point to `%TEMP%/dotfiles-skills-*.log`.
Inventory and license diagnostics are in `%TEMP%/dotfiles-skills-checks.log`.
Dry runs skip Python preparation, extension changes and skill refresh.

This checkout provides native Windows setup alongside the Mac bootstrap. The
Brewfile and agent tree are shared; Windows packages, links and templates have
separate manifests under `config/windows-*.tsv` and `apps/windows/`.

## Setup

Use a Git checkout, Windows Terminal, winget (Microsoft App Installer), and
standard PowerShell 7.4 or newer. Store-packaged PowerShell is excluded because
its filesystem redirection can reach different preference files. Windows
PowerShell 5.1 is supported only as the bootstrap bridge.

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

## Daily commands

Run from the checkout, or use `dot` after setup adds its directory to PATH:

| Command | Behavior |
|---|---|
| `bin\dot.cmd help` | List native commands |
| `bin\dot.cmd doctor -Strict` | Check runtime, policy and configured surfaces |
| `bin\dot.cmd packages-check` | Compare declared packages |
| `bin\dot.cmd packages -Apply` | Install declared package counterparts |
| `bin\dot.cmd restore-apps` | Preview template restoration |
| `bin\dot.cmd restore-apps -Apply` | Merge shipped template settings; close affected apps first |
| `bin\dot.cmd backup -Apply` | Retain curated public app templates |
| `bin\dot.cmd upgrade` | Update apps, runtimes and skills |
| `bin\dot.cmd hermes -Apply` | Apply shared-skill paths and source launcher; close Hermes first |
| `bin\dot.cmd hermes-launcher -Check` | Verify Start → Hermes selects source launch |
| `make skills` | Verify checked-in skill metadata |

Skill checks and refresh output use UTF-8 even in a legacy-code-page console;
the caller's encoding is restored afterward. Native failures remain failures.

Windows public preference files are **curated onboarding templates**. Backup and
preference Check entry points intentionally skip live capture/comparison, even
when called directly. They report this explicitly. This is not a claim that live
preferences match the templates. Restore applies only shipped settings; unshipped
extra-app surfaces are skipped. Personal dictionaries, extension inventories,
accounts, device names and host layouts should stay outside this checkout.

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
pwsh -NoProfile -File tests/test_public_windows_hermes.ps1
```
