[CmdletBinding(SupportsShouldProcess)]
param([switch]$Apply, [switch]$SkipPackages, [switch]$SkipApps, [switch]$SkipFonts)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\lib\windows-common.ps1')
Assert-DotfilesWindows
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot '.git'))) { throw 'Full Windows bootstrap requires a Git checkout, not a ZIP extraction. Clone the repository with your own authentication first; no packages or settings were changed.' }
if (-not $Apply -or $WhatIfPreference) {
    Write-Output 'Preview: install independent PowerShell 7, Git, uv, Volta and Make; restore declared packages, links, hooks and non-secret app preferences. Secrets and updates are separate explicit actions.'
    return
}
Assert-DotfilesPersistentScriptPolicy
foreach ($entry in @(@('pwsh.exe','Microsoft.PowerShell'),@('git.exe','Git.Git'),@('uv.exe','astral-sh.uv'),@('volta.exe','Volta.Volta'),@('make.exe','ezwinports.make'))) {
    $present = [bool](Get-Command $entry[0] -ErrorAction SilentlyContinue)
    if ($entry[0] -eq 'pwsh.exe') { try { $null = Resolve-DotfilesPwsh; $present = $true } catch { $present = $false } }
    if (-not $present -and $PSCmdlet.ShouldProcess($entry[1], 'Install bootstrap dependency')) {
        $installArguments = @('install','--id',$entry[1],'--exact','--source','winget','--accept-source-agreements','--accept-package-agreements','--disable-interactivity')
        if ($entry[0] -eq 'pwsh.exe') { $installArguments += @('--scope','machine','--installer-type','wix','--force') }
        Invoke-DotfilesNative winget.exe $installArguments
        $env:Path = Merge-DotfilesPath @([Environment]::GetEnvironmentVariable('Path','User'),[Environment]::GetEnvironmentVariable('Path','Machine'),$env:Path)
    }
}
$pwsh = Resolve-DotfilesPwsh
if ($PSVersionTable.PSVersion -lt [version]'7.4') {
    $arguments = @('-NoProfile','-File',$PSCommandPath,'-Apply')
    if ($SkipPackages) { $arguments += '-SkipPackages' }; if ($SkipApps) { $arguments += '-SkipApps' }
    if ($SkipFonts) { $arguments += '-SkipFonts' }
    Invoke-DotfilesNative $pwsh $arguments
    return
}
Invoke-DotfilesNative uv.exe @('python','install')
$nodeVersion = (Get-Content -LiteralPath (Join-Path $PSScriptRoot '.node-version') -Raw).Trim()
Invoke-DotfilesNative volta.exe @('install',"node@$nodeVersion")
& (Join-Path $PSScriptRoot 'scripts\setup-windows-path.ps1')
$failed = [Collections.Generic.List[string]]::new()
function Invoke-SetupStage([string]$Name,[scriptblock]$Action) {
    try { & $Action } catch { $failed.Add($Name); Write-Warning "$Name : $($_.Exception.Message)" }
}
if (-not $SkipPackages) { Invoke-SetupStage 'packages' { & (Join-Path $PSScriptRoot 'scripts\install-windows-packages.ps1') -Apply } }
if (-not $SkipPackages) {
    & (Join-Path $PSScriptRoot 'scripts\setup-windows-path.ps1')
    foreach($editor in @('code','cursor')) { Invoke-SetupStage "$editor extensions" { & (Join-Path $PSScriptRoot 'scripts\install-windows-extensions.ps1') -Editor $editor -Apply } }
}
if (-not $SkipPackages -and -not $SkipFonts) { Invoke-SetupStage 'fonts' { & (Join-Path $PSScriptRoot 'scripts\install-windows-fonts.ps1') -Apply } }
Invoke-SetupStage 'links' { & (Join-Path $PSScriptRoot 'scripts\setup-windows-tool-config.ps1') }
Invoke-SetupStage 'hooks' { & (Join-Path $PSScriptRoot 'scripts\setup-windows-hooks.ps1') }
Invoke-SetupStage 'skills' { & (Join-Path $PSScriptRoot 'scripts\check-windows-skills.ps1') }
Invoke-SetupStage 'skill engine' { & (Join-Path $PSScriptRoot 'scripts\setup-windows-skill-engine.ps1') -Apply }
if (-not $SkipApps) { Invoke-SetupStage 'restore-apps' { & (Join-Path $PSScriptRoot 'scripts\restore-apps-windows.ps1') -Apply } }
if ($failed.Count) { throw "Setup incomplete: $($failed -join ', '). Rerun the named dot commands after resolving their errors." }
Write-Output 'Setup stages completed. Run dot doctor -Strict; manual packages, account sign-in and secrets recovery are separate.'
