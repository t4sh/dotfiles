# PS5.1-compatible handoff to an independent PowerShell 7 installation.
param([Parameter(ValueFromRemainingArguments)][string[]]$Forwarded)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'dot.ps1') @Forwarded
exit $LASTEXITCODE
