#Requires -Version 7.0
[CmdletBinding()]
param([switch]$Apply, [switch]$Check)
$ErrorActionPreference='Stop'
$mode=if($Check){'Check'}else{'Restore'}
& (Join-Path $PSScriptRoot 'sync-windows-apps.ps1') -Mode $mode -Apply:$Apply
& (Join-Path $PSScriptRoot 'sync-windows-extra-apps.ps1') -Mode $mode -Apply:$Apply
