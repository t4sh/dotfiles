#Requires -Version 7.0
[CmdletBinding()]
param([switch]$DryRun)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/windows-common.ps1')
Assert-DotfilesWindows
. (Join-Path $PSScriptRoot 'lib/windows-tldr.ps1')
Update-DotfilesTldr -DryRun:$DryRun
