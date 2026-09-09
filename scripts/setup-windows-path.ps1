#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param()
# Repair user PATH without replacing existing entries. Safe to rerun.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\windows-common.ps1')
Assert-DotfilesWindows
if ($WhatIfPreference) { Write-Output 'Preview: refresh declared launchers and append installed tool paths; no changes.'; return }
$runtimePaths = @{ node = (Resolve-DotfilesVoltaRuntime 'node'); npx = (Resolve-DotfilesVoltaRuntime 'npx') }
$userRoot = [Environment]::GetFolderPath('UserProfile')
$localBin = Join-Path $userRoot '.local\bin'
New-Item -ItemType Directory -Path $localBin -Force | Out-Null
$launcher = '@echo off' + "`r`n" + 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.dotfiles\scripts\codex-windows.ps1" %*' + "`r`n"
# This small launcher is deliberately 5.1-compatible; maintenance uses independent PS7.
Write-DotfilesText (Join-Path $localBin 'codex.cmd') $launcher
Write-DotfilesText (Join-Path $localBin 'dotfiles-ssh.cmd') ('@echo off' + "`r`n" + '"%WINDIR%\System32\OpenSSH\ssh.exe" %*' + "`r`n")
foreach ($runtime in @('node','npx')) {
    Write-DotfilesText (Join-Path $localBin "$runtime-stable.cmd") ('@echo off' + "`r`n" + '"' + $runtimePaths[$runtime] + '" %*' + "`r`n")
}
$uv = Get-Command uv.exe -ErrorAction SilentlyContinue
if ($uv) {
    . (Join-Path $PSScriptRoot 'lib/windows-tldr.ps1')
    $toolsRoot = & $uv.Source tool dir
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve uv tool directory.' }
    if (Test-Path -LiteralPath (Join-Path "$toolsRoot" 'tldr/Scripts/python.exe')) {
        Set-DotfilesTldrLauncher
    }
    $pythonPath = Resolve-DotfilesPython
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $pythonPath -PathType Leaf)) {
        foreach ($name in @('python','python3')) {
            Write-DotfilesText (Join-Path $localBin "$name.cmd") ('@echo off' + "`r`n" + '"' + $pythonPath + '" %*' + "`r`n")
        }
    }
}
$wanted = @(
    $localBin
    (Join-Path (Split-Path $PSScriptRoot) 'bin')
    (Join-Path $env:ProgramFiles 'PowerShell\7')
    (Join-Path $env:WINDIR 'System32\OpenSSH')
    (Join-Path $env:LOCALAPPDATA 'Programs\Meld')
    (Join-Path $env:ProgramFiles 'Meld')
    (Join-Path ${env:ProgramFiles(x86)} 'Meld')
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')
    (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin')
    (Join-Path $env:LOCALAPPDATA 'Programs\cursor\resources\app\bin')
    (Join-Path $env:LOCALAPPDATA 'Programs\Zed\bin')
    (Join-Path $env:LOCALAPPDATA 'Programs\Paseo\resources\bin')
    (Join-Path $env:ProgramFiles 'Sublime Text')
    (Join-Path $env:ProgramFiles 'gifski')
    (Join-Path $userRoot '.cargo\bin')
    (Join-Path $userRoot '.bun\bin')
    (Join-Path $env:APPDATA 'npm')
)
$qpdf = @(Get-ChildItem -Path (Join-Path $env:ProgramFiles 'qpdf*\bin\qpdf.exe') -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending) | Select-Object -First 1
if ($qpdf) { $wanted += $qpdf.DirectoryName }
$ghostscript = @(Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Programs\Ghostscript\*\bin\gswin64c.exe'),(Join-Path $env:ProgramFiles 'gs\*\bin\gswin64c.exe') -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending) | Select-Object -First 1
if ($ghostscript) {
    $wanted += $ghostscript.DirectoryName
    Write-DotfilesText (Join-Path $localBin 'gs.cmd') ('@echo off' + "`r`n" + '"' + $ghostscript.FullName + '" %*' + "`r`n")
}
$oldPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$installed = @($wanted | Where-Object { Test-Path -LiteralPath $_ -PathType Container })
$newPath = Merge-DotfilesPath (@($localBin,$oldPath) + $installed)
if ($newPath -cne $oldPath) { [Environment]::SetEnvironmentVariable('Path', $newPath, 'User') }
$env:Path = Merge-DotfilesPath @($newPath,[Environment]::GetEnvironmentVariable('Path','Machine'))
Get-Command codex,node-stable,npx-stable,code,cursor,subl -ErrorAction SilentlyContinue | Select-Object Name,Source
