#Requires -Version 7.4
[CmdletBinding()]
param([switch]$Apply, [switch]$Check, [string]$HermesHome, [string]$HermesRoot, [string]$Python,
    [string]$ProgramsDirectory = [Environment]::GetFolderPath('Programs'),
    [string]$TaskbarDirectory = (Join-Path $env:APPDATA 'Microsoft/Internet Explorer/Quick Launch/User Pinned/TaskBar'))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/windows-common.ps1')
Assert-DotfilesWindows
if ($Apply -and $Check) { throw 'Choose -Apply or -Check.' }
$HermesHome = Resolve-DotfilesHermesHome $HermesHome
if (-not $HermesRoot) { $HermesRoot = Join-Path $HermesHome 'hermes-agent' }
if (-not $Python) { $Python = Join-Path $HermesRoot 'venv/Scripts/python.exe' }
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) { throw 'Initialize Hermes before configuring its launcher.' }
Assert-DotfilesPreferenceFile $python
$target = Resolve-DotfilesPwsh
$launcher = Join-Path $PSScriptRoot 'start-windows-hermes.ps1'
foreach ($path in @($launcher,$HermesHome,$HermesRoot,$Python)) {
    if ($path.Contains('"')) { throw 'Hermes launcher paths must not contain double quotes.' }
}
$arguments = '-NoLogo -NoProfile -WindowStyle Hidden -File "' + $launcher + '" -HermesHome "' + $HermesHome + '" -HermesRoot "' + $HermesRoot + '" -Python "' + $Python + '"'
$path = Join-Path $ProgramsDirectory 'Hermes.lnk'
if (-not $Apply -and -not $Check) { Write-Output "Preview: $path will own Hermes's app identity and launch source mode; conflicting shortcuts owned by this install will be backed up."; return }
. (Join-Path $PSScriptRoot 'lib/windows-shortcuts.ps1')
$appId = 'com.nousresearch.hermes'
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($path)
$icon = @('apps/desktop/assets/icon.ico', 'apps/desktop/release/win-unpacked/Hermes.exe') |
    ForEach-Object { Join-Path $HermesRoot $_ } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $icon) { throw 'Hermes Desktop icon is missing; verify the installed desktop assets before configuring its launcher.' }
Assert-DotfilesPreferenceFile $icon
$iconLocation = $icon + ',0'
$matches = (Test-Path -LiteralPath $path) -and $shortcut.TargetPath -ieq $target -and $shortcut.Arguments -ceq $arguments -and
    $shortcut.WorkingDirectory -ieq $HOME -and [Dotfiles.ShortcutIdentity]::Get($path) -ceq $appId -and
    $shortcut.IconLocation -ieq $iconLocation
# Electron can register its bare runtime under Hermes's identity in source mode.
# Retire only conflicting links whose executable belongs to this install; never
# take over an identity registered to an unrelated installation or application.
$runtimePrefix = [IO.Path]::GetFullPath($HermesRoot).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
$programsPrefix = [IO.Path]::GetFullPath($ProgramsDirectory).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
function Read-ShortcutIdentity([string]$LinkPath, [bool]$Owned) {
    try { [Dotfiles.ShortcutIdentity]::Get($LinkPath) }
    catch {
        if ($Owned) { throw "Cannot read the Hermes shortcut identity: $LinkPath" }
        Write-Warning "Skipping unreadable unrelated shortcut: $LinkPath"
        return $null
    }
}
$conflicts = @(if (Test-Path -LiteralPath $ProgramsDirectory) {
    Get-ChildItem -LiteralPath $ProgramsDirectory -Filter '*.lnk' -Recurse -File -Force | ForEach-Object {
        if ($_.FullName -ine [IO.Path]::GetFullPath($path)) {
            $other = $shell.CreateShortcut($_.FullName)
            $otherTarget = if ($other.TargetPath) { [IO.Path]::GetFullPath($other.TargetPath) } else { '' }
            $owned = $otherTarget.StartsWith($runtimePrefix, [StringComparison]::OrdinalIgnoreCase) -and
                [IO.Path]::GetFileName($otherTarget) -in @('electron.exe','Hermes.exe')
            $otherId = Read-ShortcutIdentity $_.FullName $owned
            if ($null -ne $otherId -and ($otherId -ceq $appId -or $owned)) {
                if (-not $owned -or ($otherId -and $otherId -cne $appId)) {
                    throw 'Hermes app identity belongs to another launcher; resolve that conflict before applying. No shortcuts changed.'
                }
                $_.FullName
            }
        }
    }
})
# A taskbar pin is a separate shortcut. Keep its path and position, but repair its
# launch command and icon in place; changing only Start leaves the bare pin broken.
$pinnedDrift = @(if (Test-Path -LiteralPath $TaskbarDirectory) {
    Get-ChildItem -LiteralPath $TaskbarDirectory -Filter '*.lnk' -File -Force | ForEach-Object {
        $pin = $shell.CreateShortcut($_.FullName)
        $pinTarget = if ($pin.TargetPath) { [IO.Path]::GetFullPath($pin.TargetPath) } else { '' }
        $ownsRuntime = $pinTarget.StartsWith($runtimePrefix, [StringComparison]::OrdinalIgnoreCase) -and
            [IO.Path]::GetFileName($pinTarget) -in @('electron.exe','Hermes.exe')
        $ownsLauncher = $pin.TargetPath -ieq $target -and $pin.Arguments.Contains('-File "' + $launcher + '"')
        $pinId = Read-ShortcutIdentity $_.FullName ($ownsRuntime -or $ownsLauncher)
        if ($null -ne $pinId -and ($pinId -ceq $appId -or $ownsRuntime -or $ownsLauncher)) {
            if (-not $ownsRuntime -and -not $ownsLauncher) {
                throw 'Hermes taskbar identity belongs to another launcher; resolve that conflict before applying. No shortcuts changed.'
            }
            if ($pinId -and $pinId -cne $appId) { throw 'Hermes taskbar target has another app identity; resolve that conflict before applying. No shortcuts changed.' }
            if ($pin.TargetPath -ine $target -or $pin.Arguments -cne $arguments -or $pin.WorkingDirectory -ine $HOME -or
                $pin.IconLocation -ine $iconLocation -or $pinId -cne $appId) { $_.FullName }
        }
    }
})
if ($Check -and (-not $matches -or $conflicts.Count -or $pinnedDrift.Count)) { throw 'Hermes launcher differs or has conflicting Start/taskbar identity; run dot hermes-launcher -Apply.' }
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
    $shortcut.IconLocation = $iconLocation
    $shortcut.Save()
    [Dotfiles.ShortcutIdentity]::Set($path, $appId)
}
if ($Apply) {
    foreach ($pinPath in $pinnedDrift) {
        $backup = $pinPath + '.before-dotfiles'
        if (-not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $pinPath -Destination $backup }
        Copy-Item -LiteralPath $path -Destination $pinPath -Force
        [Dotfiles.ShortcutIdentity]::Notify($pinPath)
        Write-Output 'Repaired existing Hermes taskbar pin (original shortcut backed up).'
    }
    foreach ($conflict in $conflicts) {
        $backup = $conflict + '.before-dotfiles'
        if (Test-Path -LiteralPath $backup) { $backup += '-' + [guid]::NewGuid().ToString('N') }
        foreach ($candidate in @($conflict, $backup)) {
            if (-not [IO.Path]::GetFullPath($candidate).StartsWith($programsPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Shortcut backup escaped Programs directory.' }
        }
        Move-Item -LiteralPath $conflict -Destination $backup
        [Dotfiles.ShortcutIdentity]::NotifyMove($conflict, $backup)
        Write-Output "Backed up conflicting Hermes shortcut: $backup"
    }
    [Dotfiles.ShortcutIdentity]::Notify($path)
}
Write-Output 'Hermes launcher: Start and existing taskbar pins use source mode and the Hermes app identity.'
