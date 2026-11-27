#Requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory, ParameterSetName='Apply')][switch]$Apply,
    [Parameter(Mandatory, ParameterSetName='Check')][switch]$Check,
    [string]$UserRoot = [Environment]::GetFolderPath('UserProfile'),
    [string]$ConfigRoot = $(if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $UserRoot '.claude' }),
    [string]$Python
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\windows-common.ps1')
Assert-DotfilesWindows
if (-not [IO.Path]::IsPathFullyQualified($ConfigRoot)) { throw 'Claude config directory must be an absolute path.' }
$settings = Join-Path $ConfigRoot 'settings.json'
if (Test-Path -LiteralPath $settings -PathType Leaf) { Assert-DotfilesPreferenceFile $settings }
$root = Split-Path $PSScriptRoot
$python = if ($Python) {
    if (-not [IO.Path]::IsPathFullyQualified($Python) -or -not (Test-Path -LiteralPath $Python -PathType Leaf)) { throw 'Python override must be an existing absolute executable path.' }
    Assert-DotfilesPythonRuntime -Path $Python -Label 'Selected Python'
    $Python
} else { Resolve-DotfilesPython }
$action = if ($Apply) { 'restore' } else { 'check' }
Invoke-DotfilesNative $python @(
    '-B', (Join-Path $root 'scripts/claude-settings.py'), $action,
    '--snapshot', (Join-Path $root 'config/claude/settings.json'),
    '--settings', $settings
)
