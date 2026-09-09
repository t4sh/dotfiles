#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param([switch]$Check, [string]$UserRoot = [Environment]::GetFolderPath('UserProfile'),
    [string]$RoamingRoot = $env:APPDATA, [string]$LocalRoot = $env:LOCALAPPDATA,
    [string]$DocumentsRoot = [Environment]::GetFolderPath('MyDocuments'),
    [string]$Manifest = (Join-Path (Split-Path $PSScriptRoot) 'config\windows-links.tsv'))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\windows-common.ps1')
. (Join-Path $PSScriptRoot 'lib\windows-links.ps1')
Assert-DotfilesWindows
$root = Split-Path $PSScriptRoot
$variables = @{DOTFILES=$root;HOME=$UserRoot;APPDATA=$RoamingRoot;LOCALAPPDATA=$LocalRoot;DOCUMENTS=$DocumentsRoot}
$failures = @()
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
# Validate the complete manifest before touching the first consumer.
$mappings = foreach ($row in (Import-Csv -LiteralPath $Manifest -Delimiter "`t")) {
    if ($row.Source -notmatch '^\$\{DOTFILES\}[\\/]' -or $row.Target -notmatch '^\$\{(HOME|APPDATA|LOCALAPPDATA|DOCUMENTS)\}[\\/]' -or ($row.Source+';'+$row.Target) -match '(^|[\\/])\.\.?([\\/;]|$)') { throw 'Manifest paths must be rooted in declared directories without dot segments.' }
    $source = $row.Source; $target = $row.Target
    foreach ($key in $variables.Keys) {
        $source = $source.Replace(('$'+'{'+$key+'}'),$variables[$key])
        $target = $target.Replace(('$'+'{'+$key+'}'),$variables[$key])
    }
    if ($source -match '\$\{' -or $target -match '\$\{') { throw 'Unresolved manifest variable' }
    $source = [IO.Path]::GetFullPath($source); $target = [IO.Path]::GetFullPath($target)
    if (-not $source.StartsWith(([IO.Path]::GetFullPath($root).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)) { throw 'Source escaped the repository.' }
    if (-not $seen.Add($target)) { throw "Duplicate manifest target: $target" }
    if (-not (Test-Path -LiteralPath $source)) { throw "Missing source: $source" }
    @{Source=$source;Target=$target}
}
foreach ($mapping in $mappings) {
    $source=$mapping.Source; $target=$mapping.Target
    try {
        $mode = Get-DotfilesLinkMode $source $target
        if ($mode -in @('SymbolicLink','HardLink','Junction')) { Write-Output "$mode : $target"; continue }
        if ($Check) { throw "Drift ($mode): $target" }
        if ($PSCmdlet.ShouldProcess($target,"Link to $source")) { Set-DotfilesLink $source $target }
    } catch { $failures += $_.Exception.Message; Write-Warning $_.Exception.Message }
}
if ($failures.Count) { throw "Configuration has $($failures.Count) failed mapping(s)." }
