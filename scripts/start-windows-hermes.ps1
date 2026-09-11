#Requires -Version 7.4
[CmdletBinding()]
param([string]$HermesHome, [string]$HermesRoot)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/windows-common.ps1')
Assert-DotfilesWindows
if (-not $HermesHome) { $HermesHome = Join-Path $env:LOCALAPPDATA 'hermes' }
if (-not $HermesRoot) { $HermesRoot = Join-Path $HermesHome 'hermes-agent' }
$env:HERMES_HOME = $HermesHome
$env:HERMES_DESKTOP_HERMES_ROOT = $HermesRoot
$python = Join-Path $HermesRoot 'venv/Scripts/python.exe'
Assert-DotfilesPreferenceFile $python
Assert-DotfilesPreferenceFile (Join-Path $HermesRoot 'hermes_cli/main.py')
# Normal desktop launch never installs, updates or rebuilds anything.
Invoke-DotfilesNativeUtf8 $python @('-u','-m','hermes_cli.main','desktop','--source','--skip-build')
