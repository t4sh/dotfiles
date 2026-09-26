#Requires -Version 7.4
# Public-owned fixture. Does not install, link, restore, or read live preferences.
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Run this fixture on native Windows.' }
$root = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-public-'+[guid]::NewGuid().ToString('N'))
$savedRoaming = $env:APPDATA
$savedLocal = $env:LOCALAPPDATA
function TreeHash([string]$Path) {
    return (@(Get-ChildItem -LiteralPath $Path -Recurse -File | Sort-Object FullName | ForEach-Object {
        $_.FullName.Substring($Path.Length) + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }) -join "`n")
}
try {
    $env:APPDATA = Join-Path $fixture 'Roaming'
    $env:LOCALAPPDATA = Join-Path $fixture 'Local'
    $snapshot = Join-Path $fixture 'snapshots'
    New-Item -ItemType Directory -Path $fixture | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'apps/windows') -Destination $snapshot -Recurse
    $dummy = Join-Path $env:APPDATA 'Code/User/settings.json'
    New-Item -ItemType Directory -Path (Split-Path $dummy) -Force | Out-Null
    [IO.File]::WriteAllText($dummy, '{"editor.fontSize":52,"cSpell.words":["dummy-personal-word"]}')
    New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force | Out-Null
    # Restore Mac-authored Zed sources into this disposable profile before Check.
    if (Test-Path -LiteralPath (Join-Path $root 'apps/windows/zed/settings.json')) { throw 'Windows-authored Zed settings must not ship.' }
    if (Test-Path -LiteralPath (Join-Path $root 'apps/windows/extra/zed/keymap.json')) { throw 'Windows-authored Zed keymap must not ship.' }
    & (Join-Path $root 'scripts/sync-windows-apps.ps1') -Mode Restore -Only zed -Apply -RoamingRoot $env:APPDATA -SnapshotRoot $snapshot
    & (Join-Path $root 'scripts/sync-windows-extra-apps.ps1') -Mode Restore -Only zed -Apply -RoamingRoot $env:APPDATA -LocalRoot $env:LOCALAPPDATA -UserRoot $fixture -RegistryRoot 'HKCU:\Software\DotfilesPublicFixtureAbsent' -SnapshotRoot (Join-Path $snapshot 'extra')
    foreach ($file in @('settings.json','keymap.json')) {
        if (-not (Test-Path -LiteralPath (Join-Path $env:APPDATA "Zed/$file"))) { throw "Shared Zed $file was not restored." }
    }
    $before = TreeHash $snapshot
    $repoBefore = TreeHash (Join-Path $root 'apps')
    $liveBefore = TreeHash $fixture
    foreach ($mode in @('Backup','Check')) {
        & (Join-Path $root 'scripts/sync-windows-apps.ps1') -Mode $mode -Apply -RoamingRoot $env:APPDATA -SnapshotRoot $snapshot
        & (Join-Path $root 'scripts/sync-windows-extra-apps.ps1') -Mode $mode -Apply -RoamingRoot $env:APPDATA -LocalRoot $env:LOCALAPPDATA -UserRoot $fixture -RegistryRoot 'HKCU:\Software\DotfilesPublicFixtureAbsent' -SnapshotRoot (Join-Path $snapshot 'extra')
    }
    & (Join-Path $root 'scripts/backup-apps-windows.ps1') -Apply
    if ((TreeHash $snapshot) -cne $before) { throw 'Public fixture templates changed.' }
    if ((TreeHash (Join-Path $root 'apps')) -cne $repoBefore) { throw 'Public repository templates changed.' }
    if ((TreeHash $fixture) -cne $liveBefore) { throw 'Dummy live preferences changed.' }
    Write-Output 'PASS: public backup preserves templates; shared Zed sources restore and check.'
} finally {
    $env:APPDATA = $savedRoaming
    $env:LOCALAPPDATA = $savedLocal
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
