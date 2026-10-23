#Requires -Version 7.0
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
. (Join-Path $root 'scripts/lib/windows-app-groups.ps1')
$passed = 0
function Assert-Group([bool]$Condition,[string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:passed++
    Write-Output "PASS: $Name"
}
function Assert-Rejected([scriptblock]$Action,[string]$Name) {
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert-Group $rejected $Name
}
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-app-groups-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory((Join-Path $fixture 'config')) | Out-Null
try {
    [IO.File]::WriteAllText((Join-Path $fixture 'Brewfile'), "cask `"alpha`"`ncask `"beta`"`ncask `"gamma`"`ncask `"font-example`"`n")
    $manifest = Join-Path $fixture 'config/app-groups.tsv'
    $valid = "Key`tGroup`ncask:alpha`tessentials`ncask:beta`tmedia`ncask:gamma`tutilities`n"
    [IO.File]::WriteAllText($manifest, $valid)
    $chosen = Get-DotfilesAppGroups -Root $fixture -AppGroups 'media'
    Assert-Group ('cask:alpha' -in $chosen.SelectedKeys -and 'cask:beta' -in $chosen.SelectedKeys -and 'cask:gamma' -in $chosen.DeferredKeys) 'named selection includes essentials and defers other casks'
    $none = Get-DotfilesAppGroups -Root $fixture -AppGroups 'none'
    Assert-Group ($none.SelectedKeys.Count -eq 0 -and $none.DeferredKeys.Count -eq 3) 'none defers every app cask'
    $fonts = Get-DotfilesAppGroups -Root $fixture -AppGroups 'fonts'
    Assert-Group ($fonts.SelectedKeys.Count -eq 1 -and $fonts.SelectedKeys[0] -eq 'cask:alpha' -and 'fonts' -in $fonts.Groups) 'fonts selects derived fonts and essentials without other casks'
    Assert-Rejected { Get-DotfilesAppGroups -Root $fixture -AppGroups 'Media' } 'group names use canonical lowercase'
    Assert-Rejected { Get-DotfilesAppGroups -Root $fixture -AppGroups 'media,media' } 'duplicate group selection rejected'
    Assert-Rejected { Get-DotfilesAppGroups -Root $fixture -AppGroups 'all,media' } 'all cannot be combined'
    Assert-Rejected { Get-DotfilesAppGroups -Root $fixture -AppGroups 'unknown' } 'unknown group rejected'
    [IO.File]::WriteAllText($manifest, "Key`tGroup`ncask:alpha`tessentials`ncask:beta`tmedia`n")
    Assert-Rejected { Get-DotfilesAppGroups -Root $fixture } 'missing cask mapping rejected'
    [IO.File]::AppendAllText((Join-Path $fixture 'Brewfile'), "  cask `"indented`"`n")
    [IO.File]::WriteAllText($manifest, $valid)
    Assert-Rejected { Get-DotfilesAppGroups -Root $fixture } 'indented Brewfile cask cannot bypass manifest coverage'
    [IO.File]::WriteAllText((Join-Path $fixture 'Brewfile'), "cask `"alpha`"`ncask `"beta`"`ncask `"gamma`"`ncask `"font-example`"`n")
    [IO.File]::WriteAllText($manifest, $valid + "cask:beta`tmedia`n")
    Assert-Rejected { Get-DotfilesAppGroups -Root $fixture } 'duplicate cask mapping rejected'
    [IO.File]::WriteAllText($manifest, $valid + "cask:stale`tmedia`n")
    Assert-Rejected { Get-DotfilesAppGroups -Root $fixture } 'stale cask mapping rejected'
    [IO.File]::WriteAllText($manifest, $valid.Replace("cask:beta`tmedia", "cask:beta`tMedia"))
    Assert-Rejected { Get-DotfilesAppGroups -Root $fixture } 'noncanonical group mapping rejected'
    [IO.File]::WriteAllText($manifest, $valid.Replace("Key`tGroup", "Package`tGroup"))
    Assert-Rejected { Get-DotfilesAppGroups -Root $fixture } 'invalid manifest header rejected'
    [IO.File]::WriteAllText($manifest, $valid)
    $rows = @(
        [pscustomobject]@{Key='brew:cli';Mode='native';Source='winget';Id='Tools.Cli'},
        [pscustomobject]@{Key='cask:alpha';Mode='native';Source='winget';Id='Shared.App'},
        [pscustomobject]@{Key='cask:beta';Mode='native';Source='winget';Id='Shared.App'},
        [pscustomobject]@{Key='cask:gamma';Mode='native';Source='winget';Id='Other.App'},
        [pscustomobject]@{Key='mas:123';Mode='native';Source='winget';Id='Shared.App'},
        [pscustomobject]@{Key='mas:456';Mode='native';Source='msstore';Id='Store.Unique'}
    )
    $packages = @(Select-DotfilesWindowsPackages -Rows $rows -Selection $chosen)
    Assert-Group ($packages.Count -eq 2 -and @($packages | Where-Object Id -EQ 'Shared.App').Count -eq 1) 'named group keeps selected cask counterpart and defers App Store mappings before dedup'
    $packages = @(Select-DotfilesWindowsPackages -Rows $rows -Selection $none)
    Assert-Group ($packages.Count -eq 1 -and $packages[0].Id -eq 'Tools.Cli') 'none keeps native CLI baseline and excludes cask and App Store counterparts'
    $all = Get-DotfilesAppGroups -Root $fixture -AppGroups 'all'
    $packages = @(Select-DotfilesWindowsPackages -Rows $rows -Selection $all)
    Assert-Group ($packages.Count -eq 4 -and @($packages | Where-Object Id -EQ 'Shared.App').Count -eq 1 -and @($packages | Where-Object Id -EQ 'Store.Unique').Count -eq 1) 'all includes App Store counterpart and deduplicates shared ID'
    $statusScripts = Join-Path $fixture 'scripts'
    [IO.Directory]::CreateDirectory((Join-Path $statusScripts 'lib')) | Out-Null
    Copy-Item (Join-Path $root 'scripts/setup-status-windows.ps1') (Join-Path $statusScripts 'setup-status-windows.ps1')
    Copy-Item (Join-Path $root 'scripts/lib/windows-app-groups.ps1') (Join-Path $statusScripts 'lib/windows-app-groups.ps1')
    [IO.File]::WriteAllText((Join-Path $fixture '.node-version'), "v22.23.1`n")
    $nodeCmd = Join-Path $fixture 'node-stable.cmd'
    [IO.File]::WriteAllText($nodeCmd, "@echo off`r`necho v22.23.1`r`n")
    $commonStub = @'
function Assert-DotfilesWindows {}
function Resolve-DotfilesPwsh { 'fixture-pwsh' }
function Resolve-DotfilesPython { 'fixture-python' }
function Get-Command { param($Name,$ErrorAction); if ($Name -in @('node-stable','npx-stable')) { [pscustomobject]@{Source=$nodeCmd} } else { throw "Unexpected command: $Name" } }
'@
    [IO.File]::WriteAllText((Join-Path $statusScripts 'lib/windows-common.ps1'), $commonStub)
    $packagesStub = @'
function Get-DotfilesWindowsPackages {
    @(
        [pscustomobject]@{Key='brew:cli';Mode='native';Source='winget';Id='Tools.Cli'},
        [pscustomobject]@{Key='cask:alpha';Mode='native';Source='winget';Id='Alpha.App'},
        [pscustomobject]@{Key='cask:beta';Mode='native';Source='winget';Id='Beta.App'},
        [pscustomobject]@{Key='mas:123';Mode='native';Source='winget';Id='Alpha.App'},
        [pscustomobject]@{Key='mas:789';Mode='manual';Source='';Id=''}
    )
}
function Get-DotfilesWindowsInventory { param([switch]$ReadOnly); if (-not $ReadOnly) { throw 'unsafe inventory mode' }; @{ 'winget:Tools.Cli'='1.0'; 'winget:Alpha.App'='1.0' } }
'@
    [IO.File]::WriteAllText((Join-Path $statusScripts 'lib/windows-packages.ps1'), $packagesStub)
    [IO.File]::WriteAllText((Join-Path $statusScripts 'setup-windows-tool-config.ps1'), 'param([switch]$Check); if (-not $Check) { throw "unsafe link apply" }; throw "fixture link drift"')
    [IO.File]::WriteAllText((Join-Path $statusScripts 'setup-windows-hooks.ps1'), 'param([switch]$Check); if (-not $Check) { throw "unsafe hook apply" }; "hooks checked"')
    [IO.File]::WriteAllText((Join-Path $statusScripts 'check-windows-skills.ps1'), '"skills checked"')
    [IO.File]::WriteAllText((Join-Path $statusScripts 'setup-windows-skill-engine.ps1'), 'param([switch]$Apply); if ($Apply) { throw "unsafe engine apply" }; "engine checked"')
    $statusOutput = @()
    $statusError = ''
    try { & (Join-Path $statusScripts 'setup-status-windows.ps1') -AppGroups media | ForEach-Object { $script:statusOutput += $_ } }
    catch { $statusError = $_.Exception.Message }
    Assert-Group ($statusError -like '*native packages*' -and $statusError -like '*links*' -and $statusOutput -like '*MISSING cask:beta*') 'status aggregates package and link failures'
    Assert-Group (@($statusOutput -like '*App Store mappings: 2 deferred (all-only)*').Count -gt 0) 'partial status reports native and manual App Store mappings deferred'
    Assert-Group ($statusOutput -contains 'OK hooks' -and $statusOutput -contains 'OK skills' -and $statusOutput -contains 'OK skill engine') 'status continues read-only checks after failures'
    [IO.File]::WriteAllText((Join-Path $statusScripts 'install-windows-extensions.ps1'), 'param($Editor,[switch]$Check); if (-not $Check) { throw "unsafe extension apply" }')
    [IO.File]::WriteAllText((Join-Path $statusScripts 'restore-apps-windows.ps1'), 'param([switch]$Check); if (-not $Check) { throw "unsafe preference restore" }')
    $statusOutput = @()
    try { & (Join-Path $statusScripts 'setup-status-windows.ps1') -AppGroups all | ForEach-Object { $script:statusOutput += $_ } } catch {}
    Assert-Group (@($statusOutput -like '*Manual app installs: mas:789*').Count -gt 0) 'full status lists manual App Store mapping'
    Write-Output "Windows app-group fixtures passed: $passed checks."
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    $prefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\dotfiles-app-groups-'
    if ($resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
