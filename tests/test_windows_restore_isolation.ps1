#Requires -Version 7.4
# Execute the real wrapper with disposable roots and stage spies; no OS/app calls.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-restore-isolation-' + [guid]::NewGuid().ToString('N'))
$previousAppData = $env:APPDATA
$previousProgramFiles = $env:ProgramFiles
function Assert($condition, [string]$message) { if (-not $condition) { throw $message } }
try {
    $scripts = Join-Path $fixture scripts
    New-Item -ItemType Directory -Force (Join-Path $scripts lib) | Out-Null
    $restore = Join-Path $scripts restore-apps-windows.ps1
    Copy-Item (Join-Path $repo scripts/restore-apps-windows.ps1) $restore
    Set-Content (Join-Path $scripts lib/windows-common.ps1) 'function Assert-DotfilesWindows {}'
    Set-Content (Join-Path $scripts lib/windows-links.ps1) '# No link operations in targeted editor restore.'
    $spy = @'
param($Mode, [switch]$Apply, [switch]$Check, $Only, $RoamingRoot, $BackupRoot, $Editor, $ExtensionsDir, $UserDataDir)
$entry = @{} + $PSBoundParameters
$entry.Stage = [IO.Path]::GetFileName($PSCommandPath)
$global:DotfilesRestoreIsolationCalls.Add($entry)
'@
    foreach ($name in @('sync-windows-apps.ps1', 'install-windows-extensions.ps1')) {
        Set-Content (Join-Path $scripts $name) $spy
    }
    $env:APPDATA = Join-Path $fixture live
    $env:ProgramFiles = Join-Path $fixture programs
    $isolated = Join-Path $fixture isolated
    $extensions = Join-Path $fixture extensions
    $global:DotfilesRestoreIsolationCalls = [Collections.Generic.List[object]]::new()
    foreach ($editor in @('vscode', 'cursor')) {
        foreach ($mode in @('Preview', 'Apply', 'Check')) {
            $flags = @{}
            if ($mode -ne 'Preview') { $flags[$mode] = $true }
            foreach ($partial in @(
                @{ExtensionsDir=$extensions},
                @{ExtensionsDir=$extensions; RoamingRoot=(Join-Path $env:APPDATA '.')},
                @{RoamingRoot=$isolated}
            )) {
                $global:DotfilesRestoreIsolationCalls.Clear()
                $rejected = $false
                try { & $restore -Only $editor @flags @partial } catch {
                    $rejected = $_.Exception.Message -like '*isolated editor restore requires*'
                }
                Assert $rejected "$editor $mode accepted partial isolation or failed for another reason"
                Assert ($global:DotfilesRestoreIsolationCalls.Count -eq 0) 'Partial isolation reached a preference/extension stage'
                Assert (-not (Test-Path $env:APPDATA)) 'Partial isolation created the live profile'
            }
            foreach ($scope in @(@{}, @{RoamingRoot=$isolated; ExtensionsDir=$extensions})) {
                $global:DotfilesRestoreIsolationCalls.Clear()
                & $restore -Only $editor @flags @scope
                Assert ($global:DotfilesRestoreIsolationCalls.Count -eq 2) 'Valid restore did not reach both stages'
                $preferences, $install = $global:DotfilesRestoreIsolationCalls
                $expectedRoot = if ($scope.Count) { $isolated } else { $env:APPDATA }
                Assert ($preferences.RoamingRoot -eq $expectedRoot) 'Preferences targeted the wrong profile'
                if ($scope.Count) {
                    $directory = if ($editor -eq 'vscode') { 'Code' } else { 'Cursor' }
                    Assert ($install.UserDataDir -eq (Join-Path $isolated $directory)) 'Editor data escaped isolation'
                    Assert ($install.ExtensionsDir -eq $extensions) 'Extensions escaped isolation'
                } else {
                    Assert (-not $install.ContainsKey('UserDataDir') -and -not $install.ContainsKey('ExtensionsDir')) 'Default restore changed scope'
                }
            }
        }
    }
    Write-Output 'PASS: restore isolation rejects both missing halves before stages; default and complete scopes preserved (30 cases).'
} finally {
    $env:APPDATA = $previousAppData
    $env:ProgramFiles = $previousProgramFiles
    Remove-Variable DotfilesRestoreIsolationCalls -Scope Global -ErrorAction SilentlyContinue
    if (Test-Path $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
