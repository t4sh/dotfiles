[CmdletBinding(SupportsShouldProcess)]
param([switch]$Apply, [switch]$SkipPackages, [switch]$SkipApps, [switch]$SkipFonts,
    [string]$AppGroups = $(if ($env:APP_GROUPS) { $env:APP_GROUPS } else { 'all' }))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\lib\windows-common.ps1')
Assert-DotfilesWindows
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot '.git'))) { throw 'Full Windows bootstrap requires a Git checkout, not a ZIP extraction. Clone the repository with your own authentication first; no packages or settings were changed.' }
. (Join-Path $PSScriptRoot 'scripts\lib\windows-app-groups.ps1')
. (Join-Path $PSScriptRoot 'scripts\lib\windows-packages.ps1')
$selection = Get-DotfilesAppGroups -Root $PSScriptRoot -AppGroups $AppGroups
$null = Get-DotfilesWindowsPackages -Root $PSScriptRoot
if (-not $Apply -or $WhatIfPreference) {
    $preferences = if ('all' -in $selection.Groups -and -not $SkipApps) { 'restore non-secret app preferences' } else { 'preserve app preferences (aggregate restore skipped)' }
    $packages = if ($SkipPackages) { 'skip declared packages, fonts and editor extensions' } else { 'install selected declared packages and any selected font/editor-extension groups' }
    Write-Output "Preview: app groups $($selection.Groups -join ', '); install independent PowerShell 7, Git, uv, Volta and Make; $packages; configure links and hooks; $preferences. Secrets and updates are separate explicit actions."
    return
}
$failed = [Collections.Generic.List[string]]::new()
$completed = [Collections.Generic.List[string]]::new()
$skipped = [Collections.Generic.List[string]]::new()
$bootstrapCmdlet = $PSCmdlet
function Invoke-BootstrapPrerequisite([string]$Name,[string]$Retry,[scriptblock]$Action) {
    try { & $Action; $completed.Add($Name) }
    catch {
        Write-Output "Completed: $(if ($completed.Count) { $completed -join ', ' } else { 'none' })"
        Write-Output "Failed: $Name : $($_.Exception.Message)"
        Write-Output 'Skipped: later setup stages were not started.'
        Write-Output 'Manual: app sign-ins, paid activation, default-app choices and secret recovery remain unverified.'
        Write-Output "Retry: $Retry"
        throw
    }
}
Invoke-BootstrapPrerequisite 'persistent script policy' 'Set-ExecutionPolicy -Scope CurrentUser RemoteSigned; reopen PowerShell' { Assert-DotfilesPersistentScriptPolicy }
foreach ($entry in @(@('pwsh.exe','Microsoft.PowerShell'),@('git.exe','Git.Git'),@('uv.exe','astral-sh.uv'),@('volta.exe','Volta.Volta'),@('make.exe','ezwinports.make'))) {
    $dependency = $entry[1]
    Invoke-BootstrapPrerequisite "dependency $dependency" "winget install --id $dependency --exact; rerun install.ps1 -Apply -AppGroups '$AppGroups'" {
        $present = [bool](Get-Command $entry[0] -ErrorAction SilentlyContinue)
        if ($entry[0] -eq 'pwsh.exe') { try { $null = Resolve-DotfilesPwsh; $present = $true } catch { $present = $false } }
        if (-not $present -and $bootstrapCmdlet.ShouldProcess($dependency, 'Install bootstrap dependency')) {
            $installArguments = @('install','--id',$dependency,'--exact','--source','winget','--accept-source-agreements','--accept-package-agreements','--disable-interactivity')
            if ($entry[0] -eq 'pwsh.exe') { $installArguments += @('--scope','machine','--installer-type','wix','--force') }
            Invoke-DotfilesNative winget.exe $installArguments
            $env:Path = Merge-DotfilesPath @([Environment]::GetEnvironmentVariable('Path','User'),[Environment]::GetEnvironmentVariable('Path','Machine'),$env:Path)
        }
    }
}
Invoke-BootstrapPrerequisite 'independent PowerShell 7' "install.ps1 -Apply -AppGroups '$AppGroups'" { $script:pwsh = Resolve-DotfilesPwsh }
if ($PSVersionTable.PSVersion -lt [version]'7.4') {
    $arguments = @('-NoProfile','-File',$PSCommandPath,'-Apply','-AppGroups',$AppGroups)
    if ($SkipPackages) { $arguments += '-SkipPackages' }; if ($SkipApps) { $arguments += '-SkipApps' }
    if ($SkipFonts) { $arguments += '-SkipFonts' }
    Invoke-BootstrapPrerequisite 'PowerShell 7 re-entry' "install.ps1 -Apply -AppGroups '$AppGroups'" { Invoke-DotfilesNative $pwsh $arguments }
    return
}
Invoke-BootstrapPrerequisite 'Node version manifest' 'restore .node-version from the repository' { $script:nodeVersion = (Get-Content -LiteralPath (Join-Path $PSScriptRoot '.node-version') -Raw).Trim() }
Invoke-BootstrapPrerequisite 'managed Python' 'uv python install' { Invoke-DotfilesNative uv.exe @('python','install') }
Invoke-BootstrapPrerequisite "Node $nodeVersion" "volta install node@$nodeVersion" { Invoke-DotfilesNative volta.exe @('install',"node@$nodeVersion") }
Invoke-BootstrapPrerequisite 'PATH setup' 'dot path' { & (Join-Path $PSScriptRoot 'scripts\setup-windows-path.ps1') }
function Invoke-SetupStage([string]$Name,[scriptblock]$Action) {
    try { & $Action; $completed.Add($Name) } catch { $failed.Add($Name); Write-Warning "$Name : $($_.Exception.Message)" }
}
if (-not $SkipPackages) { Invoke-SetupStage 'packages' { & (Join-Path $PSScriptRoot 'scripts\install-windows-packages.ps1') -Apply -AppGroups $AppGroups } }
else { $skipped.Add('packages (-SkipPackages)') }
if (-not $SkipPackages) {
    Invoke-SetupStage 'PATH refresh' { & (Join-Path $PSScriptRoot 'scripts\setup-windows-path.ps1') }
    if ('all' -in $selection.Groups -or 'development' -in $selection.Groups) {
        foreach($editor in @('code','cursor')) { Invoke-SetupStage "$editor extensions" { & (Join-Path $PSScriptRoot 'scripts\install-windows-extensions.ps1') -Editor $editor -Apply } }
    } else { $skipped.Add('editor extensions (development not selected)') }
}
else { $skipped.Add('editor extensions (-SkipPackages)') }
if (-not $SkipPackages -and -not $SkipFonts -and ('all' -in $selection.Groups -or 'fonts' -in $selection.Groups)) { Invoke-SetupStage 'fonts' { & (Join-Path $PSScriptRoot 'scripts\install-windows-fonts.ps1') -Apply } }
else { $skipped.Add('fonts (-SkipPackages, -SkipFonts, or fonts not selected)') }
Invoke-SetupStage 'links' { & (Join-Path $PSScriptRoot 'scripts\setup-windows-tool-config.ps1') }
Invoke-SetupStage 'hooks' { & (Join-Path $PSScriptRoot 'scripts\setup-windows-hooks.ps1') }
Invoke-SetupStage 'skills' { & (Join-Path $PSScriptRoot 'scripts\check-windows-skills.ps1') }
Invoke-SetupStage 'skill engine' { & (Join-Path $PSScriptRoot 'scripts\setup-windows-skill-engine.ps1') -Apply }
if (-not $SkipApps -and 'all' -in $selection.Groups) { Invoke-SetupStage 'restore-apps' { & (Join-Path $PSScriptRoot 'scripts\restore-apps-windows.ps1') -Apply } }
else { $skipped.Add('restore-apps (-SkipApps or partial app selection)') }
if (-not $SkipApps) { Invoke-SetupStage 'Hermes skills' { & (Join-Path $PSScriptRoot 'scripts/setup-windows-hermes.ps1') -Apply -SkipMissing } }
else { $skipped.Add('Hermes skills (-SkipApps)') }
Write-Output "Completed: $(if ($completed.Count) { $completed -join ', ' } else { 'none' })"
Write-Output "Failed: $(if ($failed.Count) { $failed -join ', ' } else { 'none' })"
Write-Output "Skipped: $(if ($skipped.Count) { $skipped -join ', ' } else { 'none' })"
Write-Output "Selected app groups: $($selection.Groups -join ', '); deferred app casks: $($selection.DeferredKeys.Count)."
if ($selection.DeferredKeys.Count) {
    $deferredGroups = @($selection.Rows | Where-Object { $_.Key -in $selection.DeferredKeys } | Select-Object -ExpandProperty Group -Unique)
    Write-Output "Deferred app groups: $($deferredGroups -join ', ')."
}
Write-Output 'Manual: sign in to apps, complete paid activation and default-app choices, recover secrets if needed, then verify the consuming apps.'
Write-Output "Next: dot setup-status -AppGroups '$AppGroups'; dot doctor -Strict."
$retry = @{
    packages = "dot packages -Apply -AppGroups '$AppGroups'"
    'code extensions' = 'dot extensions -Editor code -Apply'
    'cursor extensions' = 'dot extensions -Editor cursor -Apply'
    fonts = 'dot fonts -Apply'
    links = 'dot link'
    'PATH refresh' = 'dot path'
    hooks = 'dot hooks'
    skills = 'dot skills'
    'skill engine' = 'dot skill-engine -Apply'
    'restore-apps' = 'dot restore-apps -Apply'
    'Hermes skills' = 'dot hermes -Apply'
}
foreach ($stage in $failed) { Write-Output "Retry $stage : $($retry[$stage])" }
if ($failed.Count) { throw "Setup incomplete: $($failed -join ', '). See the failed stages above." }
