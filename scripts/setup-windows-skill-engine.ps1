#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param([switch]$Apply)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\windows-common.ps1')
Assert-DotfilesWindows
$root = Split-Path $PSScriptRoot
$scripts = Join-Path $root 'agents\skills\impeccable\scripts'
$launcher = Join-Path $scripts 'impeccable.cmd'
$version = (Get-Content -LiteralPath (Join-Path $scripts 'VERSION') -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') { throw 'Invalid Impeccable engine VERSION.' }
if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) { throw 'Impeccable Windows launcher is missing. Restore the managed skill first.' }
if ($Apply -and -not $PSCmdlet.ShouldProcess("Impeccable engine $version", 'Install through the checksum-verifying launcher and probe')) { return }
$oldProbe = $env:IMPECCABLE_LAUNCHER_PROBE
try {
    # Upstream's probe mode only uses the bundled/versioned/override engine;
    # it skips PATH probes and exits before downloading or creating cache files.
    $env:IMPECCABLE_LAUNCHER_PROBE = if ($Apply) { $null } else { '1' }
    $output = @(& $launcher engine-probe)
    $status = $LASTEXITCODE
    if ($status -ne 0 -or ($output -join "`n").Trim() -cne "impeccable-engine $version") {
        throw "Impeccable engine $version is missing, incompatible or failed (exit $status). Run: dot skill-engine -Apply. If it still fails, inspect the launcher error and IMPECCABLE_BIN override."
    }
    Write-Output "Impeccable engine $version verified."
} finally { $env:IMPECCABLE_LAUNCHER_PROBE = $oldProbe }
