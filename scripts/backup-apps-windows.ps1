#Requires -Version 7.0
[CmdletBinding()]
param([switch]$Apply)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'sync-windows-apps.ps1') -Mode Backup -Apply:$Apply
& (Join-Path $PSScriptRoot 'sync-windows-extra-apps.ps1') -Mode Backup -Apply:$Apply
& (Join-Path $PSScriptRoot 'backup-raycast-windows.ps1') -Apply:$Apply
