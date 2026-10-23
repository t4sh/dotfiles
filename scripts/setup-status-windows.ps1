#Requires -Version 7.4
[CmdletBinding()]
param([string]$AppGroups = $(if ($env:APP_GROUPS) { $env:APP_GROUPS } else { 'all' }))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\windows-common.ps1')
. (Join-Path $PSScriptRoot 'lib\windows-packages.ps1')
. (Join-Path $PSScriptRoot 'lib\windows-app-groups.ps1')
Assert-DotfilesWindows
$root = Split-Path $PSScriptRoot
$selection = Get-DotfilesAppGroups -Root $root -AppGroups $AppGroups
$rows = @(Get-DotfilesWindowsPackages)
$failed = [Collections.Generic.List[string]]::new()
Write-Output "App groups: $($selection.Groups -join ', ') (essentials included with a named selection)."
foreach ($group in @('essentials','development','design','ai','media','browsers','productivity','utilities')) {
    $count = @($selection.Rows | Where-Object Group -EQ $group).Count
    $selected = @($selection.Rows | Where-Object { $_.Group -eq $group -and $_.Key -in $selection.SelectedKeys }).Count
    Write-Output "$group : $selected selected, $($count - $selected) deferred"
}
Write-Output "fonts : $(if ('all' -in $selection.Groups -or 'fonts' -in $selection.Groups) { 'selected' } else { 'deferred' }); editor extensions : $(if ('all' -in $selection.Groups -or 'development' -in $selection.Groups) { 'selected' } else { 'deferred' })"
$masRows = @($rows | Where-Object { $_.Key.StartsWith('mas:') -and $_.Mode -in @('native','runtime','manual') })
Write-Output "Windows App Store mappings: $(if ('all' -in $selection.Groups) { "$($masRows.Count) in full selection (manual entries listed below)" } else { "$($masRows.Count) deferred (all-only)" })"
$wanted = @(Select-DotfilesWindowsPackages -Rows $rows -Selection $selection | Where-Object Mode -EQ 'native')
try {
    $inventory = Get-DotfilesWindowsInventory -ReadOnly
    $missing = @($wanted | Where-Object { -not $inventory.ContainsKey($_.Source+':'+$_.Id) })
    Write-Output "Native packages: $($wanted.Count - $missing.Count) installed, $($missing.Count) missing."
    foreach ($item in $missing) { Write-Output "MISSING $($item.Key) ($($item.Source):$($item.Id)); retry: dot packages -Apply -AppGroups '$AppGroups'" }
    if ($missing.Count) { $failed.Add('native packages') }
} catch { Write-Warning "Native package inventory unknown: $($_.Exception.Message)"; $failed.Add('native package inventory') }
$manual = @($rows | Where-Object { $_.Mode -eq 'manual' -and ($_.Key -in $selection.SelectedKeys -or ('all' -in $selection.Groups -and $_.Key.StartsWith('mas:'))) })
if ($manual.Count) { Write-Output "Manual app installs: $($manual.Key -join ', '). See WINDOWS.md or their mapping notes." }
$runtime = @(Select-DotfilesWindowsPackages -Rows $rows -Selection $selection | Where-Object Mode -EQ 'runtime')
if ($runtime.Count) {
    Write-Output "Manual verification: $($runtime.Count) uv/Volta-managed packages have no local per-package version inventory in this command."
}
if ('all' -in $selection.Groups -or 'fonts' -in $selection.Groups) {
    Write-Output 'Manual verification: Brewfile font cask registration and rendering are not checked.'
}
function Test-SetupStatus([string]$Name,[string]$Retry,[scriptblock]$Action) {
    try { & $Action | Out-Null; Write-Output "OK $Name" }
    catch { Write-Warning "$Name : $($_.Exception.Message)"; Write-Output "FAILED $Name; retry: $Retry"; $failed.Add($Name) }
}
Test-SetupStatus 'independent PowerShell 7.4+' 'install.ps1 -Apply' { $null = Resolve-DotfilesPwsh }
Test-SetupStatus 'managed Python 3' 'uv python install' { $null = Resolve-DotfilesPython }
Test-SetupStatus 'pinned Node runtime' 'volta install node@<version>; dot path' {
    $expected = (Get-Content -LiteralPath (Join-Path $root '.node-version') -Raw).Trim().TrimStart('v')
    $node = (Get-Command node-stable -ErrorAction Stop).Source
    $actual = @(& $node --version 2>$null)
    if ($LASTEXITCODE -ne 0 -or $actual.Count -ne 1 -or $actual[0].Trim().TrimStart('v') -cne $expected) { throw "Expected Node $expected, found $($actual -join ', ')." }
    $null = Get-Command npx-stable -ErrorAction Stop
}
Test-SetupStatus 'links' 'dot link' { & (Join-Path $PSScriptRoot 'setup-windows-tool-config.ps1') -Check }
Test-SetupStatus 'hooks' 'dot hooks' { & (Join-Path $PSScriptRoot 'setup-windows-hooks.ps1') -Check }
Test-SetupStatus 'skills' 'dot skills' { & (Join-Path $PSScriptRoot 'check-windows-skills.ps1') }
Test-SetupStatus 'skill engine' 'dot skill-engine -Apply' { & (Join-Path $PSScriptRoot 'setup-windows-skill-engine.ps1') }
if ('all' -in $selection.Groups -or 'development' -in $selection.Groups) {
    foreach ($editor in @('code','cursor')) {
        Test-SetupStatus "$editor extensions" "dot extensions -Editor $editor -Apply" { & (Join-Path $PSScriptRoot 'install-windows-extensions.ps1') -Editor $editor -Check }
    }
}
if ('all' -in $selection.Groups) {
    Test-SetupStatus 'saved app preferences' 'dot restore-apps -Apply' { & (Join-Path $PSScriptRoot 'restore-apps-windows.ps1') -Check }
} else { Write-Output 'Saved app preference check deferred for a partial app selection.' }
Write-Output 'Manual verification: app sign-ins, paid activation, default-app choices, secret recovery and GUI behavior are not checked here.'
if ($failed.Count) { throw "Setup status found incomplete checks: $($failed -join ', ')." }
Write-Output 'Checked local setup state passed; manual items above remain unverified.'
