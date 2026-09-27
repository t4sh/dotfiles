#Requires -Version 7.4
[CmdletBinding()]
param([switch]$DryRun)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/windows-common.ps1')
. (Join-Path $PSScriptRoot 'lib/windows-hermes.ps1')
Assert-DotfilesWindows
$hermesHome = Resolve-DotfilesHermesHome
$checkout = Join-Path $hermesHome 'hermes-agent'
if (-not (Test-Path -LiteralPath $hermesHome)) {
    Write-Output 'Hermes is not installed; install from https://hermes-agent.nousresearch.com/desktop.'
    return
}
if ($DryRun) {
    Write-Output 'Preview: Hermes native update --yes, then repair its source launcher and check shared skills.'
    return
}
# Hermes owns runtime/dependency selection and updates. Source-mode Desktop
# remains separate from the packaged executable's Application Control verdict.
foreach ($relative in @('hermes_cli/main.py','.git/HEAD','.git/index','.git/shallow')) {
    $file = Join-Path $checkout $relative
    if (Test-Path -LiteralPath $file -PathType Leaf) { Assert-DotfilesPreferenceFile $file }
}
$log = Join-Path $env:TEMP ('dotfiles-hermes-update-' + [guid]::NewGuid().ToString('N') + '.log')
Write-Output "Hermes update log: $log"
try {
    $repair = Join-Path $PSScriptRoot 'repair-windows-hermes-runtime.ps1'
    & $repair -Apply -HermesHome $hermesHome
    # PowerShell can mask an OS execution-policy rejection as an encoding error.
    # Probe this install's interpreter directly; never substitute another runtime.
    $runtime = Resolve-DotfilesHermesPythonCommand -HermesRoot $checkout
    if (-not $runtime.Managed) { Assert-DotfilesPythonRuntime $runtime.File 'Hermes Python' }
    Invoke-DotfilesHermesPython -HermesHome $hermesHome -HermesRoot $checkout -Arguments @('-u','-m','hermes_cli.main','update','--yes') 2>&1 | Tee-Object -FilePath $log
    & $repair -Apply -HermesHome $hermesHome
    # Repair upstream's shortcut before checking shared skills.
    & (Join-Path $PSScriptRoot 'setup-windows-hermes-launcher.ps1') -Apply -HermesHome $hermesHome -HermesRoot $checkout
    & (Join-Path $PSScriptRoot 'setup-windows-hermes.ps1') -Check -HermesHome $hermesHome
} catch {
    $failure = "Hermes update failed: $($_.Exception.Message). Log: $log"
    Add-Content -LiteralPath $log -Value $failure -Encoding utf8
    throw $failure
}
