#Requires -Version 7.4
[CmdletBinding()]
param([switch]$Apply, [switch]$Check, [string]$HermesHome, [string]$HermesRoot,
    [string]$ProgramsDirectory = [Environment]::GetFolderPath('Programs'))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/windows-common.ps1')
Assert-DotfilesWindows
if ($Apply -and $Check) { throw 'Choose -Apply or -Check.' }
if (-not $HermesHome) { $HermesHome = Join-Path $env:LOCALAPPDATA 'hermes' }
if (-not $HermesRoot) { $HermesRoot = Join-Path $HermesHome 'hermes-agent' }
$python = Join-Path $HermesRoot 'venv/Scripts/python.exe'
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) { throw 'Initialize Hermes before configuring its launcher.' }
Assert-DotfilesPreferenceFile $python
$target = Resolve-DotfilesPwsh
$launcher = Join-Path $PSScriptRoot 'start-windows-hermes.ps1'
foreach ($path in @($launcher,$HermesHome,$HermesRoot)) {
    if ($path.Contains('"')) { throw 'Hermes launcher paths must not contain double quotes.' }
}
$arguments = '-NoLogo -NoProfile -WindowStyle Hidden -File "' + $launcher + '" -HermesHome "' + $HermesHome + '" -HermesRoot "' + $HermesRoot + '"'
$path = Join-Path $ProgramsDirectory 'Hermes.lnk'
if (-not $Apply -and -not $Check) { Write-Output "Preview: $path will launch Hermes in source mode without rebuilding."; return }
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($path)
$matches = (Test-Path -LiteralPath $path) -and $shortcut.TargetPath -ieq $target -and $shortcut.Arguments -ceq $arguments
if ($Check -and -not $matches) { throw 'Hermes Start-menu launcher differs; run dot hermes-launcher -Apply.' }
if ($Apply -and -not $matches) {
    [IO.Directory]::CreateDirectory($ProgramsDirectory) | Out-Null
    if (Test-Path -LiteralPath $path) {
        $backup = $path + '.before-dotfiles'
        if (-not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $path -Destination $backup }
    }
    $shortcut.TargetPath = $target
    $shortcut.Arguments = $arguments
    $shortcut.WorkingDirectory = $HOME
    $shortcut.Description = 'Hermes Desktop — dotfiles Windows source launch'
    $icon = Join-Path $HermesRoot 'apps/desktop/release/win-unpacked/Hermes.exe'
    if (Test-Path -LiteralPath $icon) { $shortcut.IconLocation = $icon }
    $shortcut.Save()
}
Write-Output 'Hermes Start-menu launcher: source mode configured.'
