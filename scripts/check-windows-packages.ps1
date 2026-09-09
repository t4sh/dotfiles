#Requires -Version 7.0
[CmdletBinding()]
param([switch]$CoverageOnly, [switch]$Strict)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\windows-common.ps1')
Assert-DotfilesWindows
. (Join-Path $PSScriptRoot 'lib\windows-packages.ps1')
$rows = @(Get-DotfilesWindowsPackages)
if ($CoverageOnly) { Write-Output "Windows mapping coverage complete: $($rows.Count) explicit rows; fonts and VS Code extensions derived directly from Brewfile."; return }
$inventory = Get-DotfilesWindowsInventory
$missing = 0
foreach ($row in $rows) {
    $status = $row.Mode
    if ($row.Mode -eq 'native') {
        $status = if ($inventory.ContainsKey($row.Source+':'+$row.Id)) {'Installed'} else {'Missing'; $missing++}
    }
    [pscustomobject]@{Key=$row.Key;Status=$status;Package=$row.Id;Source=$row.Source;Note=$row.Note}
}
if ($Strict -and $missing) { throw "$missing required native mapping(s) not found. Runtime packages, fonts and editor extensions require their separate checks." }
