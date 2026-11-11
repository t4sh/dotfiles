#Requires -Version 7.4
param([string]$Python)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\lib\windows-common.ps1')
Assert-DotfilesWindows
$root = Split-Path $PSScriptRoot
$pwsh = Resolve-DotfilesPwsh
$pythonArgs = if ($Python) { @('-Python',$Python) } else { @() }
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-claude-settings-' + [guid]::NewGuid().ToString('N'))
$prefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\dotfiles-claude-settings-'
$previousConfig = $env:CLAUDE_CONFIG_DIR
try {
    $config = Join-Path $fixture 'custom-claude-config'
    [IO.Directory]::CreateDirectory($config) | Out-Null
    $settings = Join-Path $config 'settings.json'
    [IO.File]::WriteAllText($settings, '{"theme":"dark","hooks":{"Stop":[]},"attribution":{"commit":"wrong"},"includeCoAuthoredBy":true}')
    $env:CLAUDE_CONFIG_DIR = $config

    Invoke-DotfilesNative $pwsh (@('-NoProfile','-File',(Join-Path $root 'scripts/setup-windows-claude-settings.ps1'),'-Apply') + $pythonArgs)
    $live = Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json -AsHashtable
    $saved = Get-Content -LiteralPath (Join-Path $root 'config/claude/settings.json') -Raw | ConvertFrom-Json -AsHashtable
    if ($live.theme -ne 'dark' -or $live.hooks.Stop.Count -ne 0) { throw 'Claude restore changed unrelated settings.' }
    foreach ($key in @('attribution','includeCoAuthoredBy')) {
        if ((ConvertTo-Json -InputObject $live[$key] -Depth 20 -Compress) -cne (ConvertTo-Json -InputObject $saved[$key] -Depth 20 -Compress)) { throw "Claude restore did not apply managed key $key." }
    }

    $before = (Get-FileHash -LiteralPath $settings -Algorithm SHA256).Hash
    Invoke-DotfilesNative $pwsh (@('-NoProfile','-File',(Join-Path $root 'scripts/setup-windows-claude-settings.ps1'),'-Apply') + $pythonArgs)
    $after = (Get-FileHash -LiteralPath $settings -Algorithm SHA256).Hash
    if ($before -cne $after) { throw 'Repeated Claude restore was not byte-idempotent.' }
    Invoke-DotfilesNative $pwsh (@('-NoProfile','-File',(Join-Path $root 'scripts/setup-windows-claude-settings.ps1'),'-Check') + $pythonArgs)

    [IO.File]::WriteAllText($settings, '{invalid')
    $invalidBefore = [IO.File]::ReadAllBytes($settings)
    $failed = $false
    try { Invoke-DotfilesNative $pwsh (@('-NoProfile','-File',(Join-Path $root 'scripts/setup-windows-claude-settings.ps1'),'-Apply') + $pythonArgs) 2>$null }
    catch { $failed = $true }
    if (-not $failed) { throw 'Invalid Claude settings unexpectedly restored.' }
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($settings)) -cne [Convert]::ToBase64String($invalidBefore)) { throw 'Invalid Claude settings were modified.' }

    Write-Output 'Windows Claude settings fixtures passed: custom config path, managed merge, unrelated-key preservation, idempotency, check, and invalid-file preservation.'
} finally {
    $env:CLAUDE_CONFIG_DIR = $previousConfig
    $resolved = [IO.Path]::GetFullPath($fixture)
    if ($resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
