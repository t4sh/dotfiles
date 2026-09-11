#Requires -Version 7.4
[CmdletBinding()]
param([string]$Command = 'help', [Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'scripts\lib\windows-common.ps1')
Assert-DotfilesWindows
$commands = [ordered]@{
    setup='install.ps1'; link='scripts/setup-windows-tool-config.ps1';
    packages='scripts/install-windows-packages.ps1'; 'packages-check'='scripts/check-windows-packages.ps1';
    fonts='scripts/install-windows-fonts.ps1'; 'restore-apps'='scripts/restore-apps-windows.ps1';
    backup='scripts/backup-apps-windows.ps1'; doctor='scripts/doctor-windows.ps1';
    hooks='scripts/setup-windows-hooks.ps1'; 
    upgrade='scripts/update-windows.ps1'; path='scripts/setup-windows-path.ps1';
    skills='scripts/check-windows-skills.ps1'; 'ssh-setup'='scripts/check-windows-ssh.ps1'
    'skill-engine'='scripts/setup-windows-skill-engine.ps1'
    hermes='scripts/setup-windows-hermes.ps1'
    'hermes-launcher'='scripts/setup-windows-hermes-launcher.ps1'
    extensions='scripts/install-windows-extensions.ps1'
    'private-snapshot'='scripts/snapshot-private-windows.ps1'
    'secrets-backup'='scripts/secrets-backup-windows.ps1'
    'secrets-open'='scripts/secrets-backup-windows.ps1'
    'secrets-close'='scripts/secrets-backup-windows.ps1'
}
if ($Command -in @('help','--help','-h')) { $commands.GetEnumerator() | Format-Table Key,Value; return }
if (-not $commands.Contains($Command)) { throw "Unsupported Windows command: $Command. Run dot help. Automated live secrets restore is deferred; macOS targets must run on Mac." }
# A new PowerShell process preserves native parameter binding for forwarded switches.
if ($Command -eq 'secrets-open') { $Arguments = @('-Action','Open') + $Arguments }
if ($Command -eq 'secrets-close') { $Arguments = @('-Action','Close') + $Arguments }
Invoke-DotfilesNative (Resolve-DotfilesPwsh) (@('-NoProfile','-File',(Join-Path $root $commands[$Command])) + $Arguments)
