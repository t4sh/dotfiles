#Requires -Version 7.0
[CmdletBinding()]
param([switch]$Check)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\windows-common.ps1')
Assert-DotfilesWindows
$root = Split-Path $PSScriptRoot
$bash = Resolve-DotfilesBash
if (-not $Check) {
    Invoke-DotfilesNative git.exe @('-C',$root,'config','--local','core.hooksPath','.githooks')
    # Use Python plistlib, not macOS plutil. Git's textconv appends the filename.
    $python = (Resolve-DotfilesPython) -replace '\\','/'
    $viewer = (Join-Path $PSScriptRoot 'plist-text.py') -replace '\\','/'
    Invoke-DotfilesNative git.exe @('-C',$root,'config','--local','diff.plist.textconv',('"'+$python+'" "'+$viewer+'"'))
    Invoke-DotfilesNative git.exe @('-C',$root,'config','--local','diff.plist.binary','true')
}
Invoke-DotfilesNative $bash @((Join-Path $PSScriptRoot 'check-hooks.sh'))
