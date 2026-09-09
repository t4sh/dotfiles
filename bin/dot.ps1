# Windows PowerShell 5.1-compatible entry point. PowerShell resolves dot.ps1
# before dot.cmd; always hand off before checking the workflow runtime.
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Forwarded)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'scripts\lib\windows-common.ps1')
& (Resolve-DotfilesPwsh) -NoLogo -NoProfile -File (Join-Path $root 'scripts\dot-windows.ps1') @Forwarded
exit $LASTEXITCODE
