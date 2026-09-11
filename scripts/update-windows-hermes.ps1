#Requires -Version 7.4
[CmdletBinding()]
param([switch]$DryRun)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/windows-common.ps1')
Assert-DotfilesWindows
$hermesHome = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $env:LOCALAPPDATA 'hermes' }
$python = Join-Path $hermesHome 'hermes-agent/venv/Scripts/python.exe'
if (-not (Test-Path -LiteralPath $hermesHome)) {
    Write-Output 'Hermes is not installed; install from https://hermes-agent.nousresearch.com/desktop.'
    return
}
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    throw 'Hermes installation is incomplete: its Python runtime is missing. Complete the official Windows installer.'
}
Assert-DotfilesPreferenceFile $python
if ($DryRun) {
    Write-Output 'Preview: Hermes native update --yes, then repair its source launcher and check shared skills.'
    return
}
# Invoke the installed Python module, avoiding unsigned generated exe launchers.
# Hermes owns update backups and local-change handling. Never reset its checkout.
$checkout = Join-Path $hermesHome 'hermes-agent'
foreach ($relative in @('hermes_cli/main.py','.git/HEAD','.git/index','.git/shallow')) {
    $file = Join-Path $checkout $relative
    if (Test-Path -LiteralPath $file -PathType Leaf) { Assert-DotfilesPreferenceFile $file }
}
$log = Join-Path $env:TEMP ('dotfiles-hermes-update-' + [guid]::NewGuid().ToString('N') + '.log')
Write-Output "Hermes update log: $log"
try {
    Invoke-DotfilesNativeUtf8 $python @('-u','-m','hermes_cli.main','update','--yes') 2>&1 | Tee-Object -FilePath $log
    & (Join-Path $PSScriptRoot 'setup-windows-hermes-launcher.ps1') -Apply -HermesHome $hermesHome -HermesRoot $checkout
    & (Join-Path $PSScriptRoot 'setup-windows-hermes.ps1') -Check -HermesHome $hermesHome
} catch {
    throw "Hermes update failed: $($_.Exception.Message). Log: $log"
}
