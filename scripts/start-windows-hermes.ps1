#Requires -Version 7.4
[CmdletBinding()]
param([string]$HermesHome, [string]$HermesRoot, [string]$Python)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/windows-common.ps1')
Assert-DotfilesWindows
$HermesHome = Resolve-DotfilesHermesHome $HermesHome
if (-not $HermesRoot) { $HermesRoot = Join-Path $HermesHome 'hermes-agent' }
$env:HERMES_HOME = $HermesHome
$env:HERMES_DESKTOP_HERMES_ROOT = $HermesRoot
if (-not $Python) { $Python = Join-Path $HermesRoot 'venv/Scripts/python.exe' }
Assert-DotfilesPreferenceFile $python
Assert-DotfilesPreferenceFile (Join-Path $HermesRoot 'hermes_cli/main.py')
# Normal desktop launch never installs, updates or rebuilds anything.
Invoke-DotfilesNativeUtf8 $python @('-u','-m','hermes_cli.main','desktop','--source','--skip-build')
