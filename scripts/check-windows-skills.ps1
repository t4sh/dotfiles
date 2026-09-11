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
        Invoke-DotfilesNativeUtf8 $python @((Join-Path $root 'scripts\gen-skillsfile.py'))
        Invoke-DotfilesNativeUtf8 $python @((Join-Path $root 'agents\compareskills.py'))
    }
    Invoke-DotfilesNativeUtf8 $python @((Join-Path $root 'scripts\gen-skillsfile.py'),'--check')
    Invoke-DotfilesNativeUtf8 $python @((Join-Path $root 'agents\compareskills.py'),'--check')
    Invoke-DotfilesNativeUtf8 $bash @((Join-Path $root 'scripts\audit-rules.sh'))
    Invoke-DotfilesNativeUtf8 $bash @((Join-Path $root 'scripts\audit-skill-licenses.sh'),'--check')
} finally { $env:PYTHON_BIN = $oldPython }
