# Windows workflow

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
| `make skills` | Verify checked-in skill metadata |

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
```
