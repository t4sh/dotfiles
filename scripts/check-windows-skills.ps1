#Requires -Version 7.0
[CmdletBinding()]
param([switch]$UpdateManifest)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\windows-common.ps1')
Assert-DotfilesWindows
$root = Split-Path $PSScriptRoot
$python = Resolve-DotfilesPython
$bash = Resolve-DotfilesBash
$oldPython = $env:PYTHON_BIN
try {
    $env:PYTHON_BIN = $python
    if ($UpdateManifest) {
        Invoke-DotfilesNative $python @((Join-Path $root 'scripts\gen-skillsfile.py'))
        Invoke-DotfilesNative $python @((Join-Path $root 'agents\compareskills.py'))
    }
    Invoke-DotfilesNative $python @((Join-Path $root 'scripts\gen-skillsfile.py'),'--check')
    Invoke-DotfilesNative $python @((Join-Path $root 'agents\compareskills.py'),'--check')
    Invoke-DotfilesNative $bash @((Join-Path $root 'scripts\audit-rules.sh'))
    Invoke-DotfilesNative $bash @((Join-Path $root 'scripts\audit-skill-licenses.sh'),'--check')
} finally { $env:PYTHON_BIN = $oldPython }
