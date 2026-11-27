#Requires -Version 7.4
# Public-owned fixture. Does not install, link, restore, or read live preferences.
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Run this fixture on native Windows.' }
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $root 'tests/test_windows_claude_settings.ps1')
if (-not $?) { throw 'Windows Claude settings fixture failed' }
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
    $extraBackupRoot = Join-Path $fixture 'extra-backups'
    New-Item -ItemType Directory -Path $fixture | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'apps/windows') -Destination $snapshot -Recurse
    $dummy = Join-Path $env:APPDATA 'Code/User/settings.json'
    New-Item -ItemType Directory -Path (Split-Path $dummy) -Force | Out-Null
    [IO.File]::WriteAllText($dummy, '{"editor.fontSize":52,"cSpell.words":["dummy-personal-word"]}')
    New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force | Out-Null
    # Restore Mac-authored Zed sources into this disposable profile before Check.
    if (Test-Path -LiteralPath (Join-Path $root 'apps/windows/zed/settings.json')) { throw 'Windows-authored Zed settings must not ship.' }
    if (Test-Path -LiteralPath (Join-Path $root 'apps/windows/extra/zed/keymap.json')) { throw 'Windows-authored Zed keymap must not ship.' }
    $zedSettings = Join-Path $env:APPDATA 'Zed/settings.json'
    New-Item -ItemType Directory -Path (Split-Path $zedSettings) -Force | Out-Null
    [IO.File]::WriteAllText($zedSettings, '{"dummy.unrelated":true,"agent_servers":{"custom":{"type":"custom","command":"dummy.exe"},"cursor":{"type":"custom","default_config_options":{"mode":"ask"}}},"terminal":{"working_directory":"dummy-path","font_fallbacks":["dummy-font"]}}')
    $zedOptions = @{Only='zed';RoamingRoot=$env:APPDATA;SnapshotRoot=$snapshot;BackupRoot=(Join-Path $fixture 'backups')}
    & (Join-Path $root 'scripts/sync-windows-apps.ps1') -Mode Restore -Apply @zedOptions
    $restored = Get-Content -LiteralPath $zedSettings -Raw | ConvertFrom-Json -AsHashtable
    $shared = Get-Content -LiteralPath (Join-Path $root 'apps/zed/settings.json') -Raw | ConvertFrom-Json -AsHashtable
    if (-not $restored['dummy.unrelated'] -or $restored.agent_servers.custom.command -ne 'dummy.exe' -or $restored.agent_servers.cursor.default_config_options.mode -ne 'ask' -or $restored.terminal.working_directory -ne 'dummy-path') { throw 'Zed restore removed unmanaged preferences.' }
    if ($restored.agent_servers.cursor.type -ne 'registry') { throw 'Zed managed leaf was not restored.' }
    if (($restored.terminal.font_fallbacks | ConvertTo-Json -Compress) -cne ($shared.terminal.font_fallbacks | ConvertTo-Json -Compress)) { throw 'Zed managed array was not replaced.' }
    & (Join-Path $root 'scripts/sync-windows-apps.ps1') -Mode Check @zedOptions
    $zedBefore = TreeHash (Split-Path $zedSettings)
    & (Join-Path $root 'scripts/sync-windows-apps.ps1') -Mode Restore -Apply @zedOptions
    if ((TreeHash (Split-Path $zedSettings)) -cne $zedBefore) { throw 'Zed repeated restore changed preferences.' }
    $restored.agent_servers.cursor.type = 'dummy-drift'
    [IO.File]::WriteAllText($zedSettings, (ConvertTo-Json -InputObject $restored -Depth 50))
    $driftDetected = $false
    try { & (Join-Path $root 'scripts/sync-windows-apps.ps1') -Mode Check @zedOptions -WarningAction SilentlyContinue }
    catch { if ($_.Exception.Message -notmatch 'Windows preferences have drift') { throw }; $driftDetected = $true }
    if (-not $driftDetected) { throw 'Zed managed leaf drift was not detected.' }
    & (Join-Path $root 'scripts/sync-windows-apps.ps1') -Mode Restore -Apply @zedOptions
    & (Join-Path $root 'scripts/sync-windows-extra-apps.ps1') -Mode Restore -Only zed -Apply -RoamingRoot $env:APPDATA -LocalRoot $env:LOCALAPPDATA -UserRoot $fixture -RegistryRoot 'HKCU:\Software\DotfilesPublicFixtureAbsent' -SnapshotRoot (Join-Path $snapshot 'extra') -BackupRoot $extraBackupRoot
    foreach ($file in @('settings.json','keymap.json')) {
        if (-not (Test-Path -LiteralPath (Join-Path $env:APPDATA "Zed/$file"))) { throw "Shared Zed $file was not restored." }
    }

    # Tower is restore-only from shipped templates. Exercise every mode with
    # disposable roots so no host profile, registry, backup, or repository file
    # can be captured or changed by this fixture.
    $towerSnapshotRoot = Join-Path $fixture 'tower-snapshots'
    $towerMainSnapshot = Join-Path $towerSnapshotRoot 'tower/main.settings'
    $towerTemplatesSnapshot = Join-Path $towerSnapshotRoot 'tower/commit_templates.settings'
    New-Item -ItemType Directory -Path (Split-Path $towerMainSnapshot) -Force | Out-Null
    [IO.File]::WriteAllText($towerMainSnapshot, '{"ShowToolbarLabels":true}')
    [IO.File]::WriteAllText($towerTemplatesSnapshot, '{"CommitTemplates":[{"name":"fixture","body":"fixture-only"}]}')
    $towerMainLive = Join-Path $env:LOCALAPPDATA 'fournova/Tower/Settings/main.settings'
    $towerTemplatesLive = Join-Path $env:LOCALAPPDATA 'fournova/Tower/Settings/commit_templates.settings'
    New-Item -ItemType Directory -Path (Split-Path $towerMainLive) -Force | Out-Null
    [IO.File]::WriteAllText($towerMainLive, '{"Unmanaged":"keep-main","ShowToolbarLabels":false}')
    [IO.File]::WriteAllText($towerTemplatesLive, '{"Unmanaged":"keep-templates","CommitTemplates":[]}')
    $otherSnapshot = Join-Path $towerSnapshotRoot 'vlc/vlcrc.json'
    New-Item -ItemType Directory -Path (Split-Path $otherSnapshot) -Force | Out-Null
    [IO.File]::WriteAllText($otherSnapshot, '{"core":{"volume":"77"}}')
    $otherLive = Join-Path $env:APPDATA 'vlc/vlcrc'
    New-Item -ItemType Directory -Path (Split-Path $otherLive) -Force | Out-Null
    [IO.File]::WriteAllText($otherLive, "[core]`nvolume=42`nfixture=live-must-not-change`n")
    $towerSnapshotBefore = TreeHash $towerSnapshotRoot
    $repoAppsBeforeTower = TreeHash (Join-Path $root 'apps')

    # Avoid coupling this fake-profile restore to whether Tower is open on the
    # operator's machine. The script receives only disposable preference roots.
    $priorGetProcess = Get-Item Function:\Get-Process -ErrorAction SilentlyContinue
    function Get-Process {
        [CmdletBinding()]
        param([string[]]$Name)
        return @()
    }
    try {
        & (Join-Path $root 'scripts/sync-windows-extra-apps.ps1') -Mode Restore -Only tower -Apply -RoamingRoot $env:APPDATA -LocalRoot $env:LOCALAPPDATA -UserRoot $fixture -RegistryRoot 'HKCU:\Software\DotfilesPublicFixtureAbsent' -SnapshotRoot $towerSnapshotRoot -BackupRoot (Join-Path $fixture 'tower-recovery')
    } finally {
        if ($priorGetProcess) { Set-Item Function:\Get-Process -Value $priorGetProcess.ScriptBlock }
        else { Remove-Item Function:\Get-Process -ErrorAction SilentlyContinue }
    }
    $restoredTowerMain = Get-Content -LiteralPath $towerMainLive -Raw | ConvertFrom-Json -AsHashtable
    $restoredTowerTemplates = Get-Content -LiteralPath $towerTemplatesLive -Raw | ConvertFrom-Json -AsHashtable
    if ($restoredTowerMain.Unmanaged -cne 'keep-main' -or $restoredTowerMain.ShowToolbarLabels -ne $true) { throw 'Tower-only restore did not apply its template while preserving unmanaged settings.' }
    if ($restoredTowerTemplates.Unmanaged -cne 'keep-templates' -or $restoredTowerTemplates.CommitTemplates.Count -ne 1 -or $restoredTowerTemplates.CommitTemplates[0].name -cne 'fixture' -or $restoredTowerTemplates.CommitTemplates[0].body -cne 'fixture-only') { throw 'Tower-only restore did not apply the commit-template fixture while preserving unmanaged settings.' }
    if ([IO.File]::ReadAllText($otherLive) -cne "[core]`nvolume=42`nfixture=live-must-not-change`n") { throw 'Tower-only restore changed an unrelated live surface.' }

    # Deliberate Tower drift remains exempt from Windows backup/check, and both
    # actions preserve the curated snapshot fixtures and all live dummy data.
    $restoredTowerMain.ShowToolbarLabels = $false
    [IO.File]::WriteAllText($towerMainLive, (ConvertTo-Json -InputObject $restoredTowerMain -Depth 20))
    $liveBeforeSkippedModes = TreeHash $fixture
    $checkOutput = & (Join-Path $root 'scripts/sync-windows-extra-apps.ps1') -Mode Check -Only tower -Apply -RoamingRoot $env:APPDATA -LocalRoot $env:LOCALAPPDATA -UserRoot $fixture -RegistryRoot 'HKCU:\Software\DotfilesPublicFixtureAbsent' -SnapshotRoot $towerSnapshotRoot -BackupRoot $extraBackupRoot | Out-String
    $backupOutput = & (Join-Path $root 'scripts/sync-windows-extra-apps.ps1') -Mode Backup -Only tower -Apply -RoamingRoot $env:APPDATA -LocalRoot $env:LOCALAPPDATA -UserRoot $fixture -RegistryRoot 'HKCU:\Software\DotfilesPublicFixtureAbsent' -SnapshotRoot $towerSnapshotRoot -BackupRoot $extraBackupRoot | Out-String
    if ($checkOutput -notmatch 'Public templates retained; live preference Check is intentionally skipped') { throw 'Tower Check did not report the public template-only skip.' }
    if ($backupOutput -notmatch 'Public templates retained; live preference Backup is intentionally skipped') { throw 'Tower Backup did not report the public template-only skip.' }
    if ((TreeHash $towerSnapshotRoot) -cne $towerSnapshotBefore) { throw 'Tower Check/Backup changed the curated template fixtures.' }
    if ((TreeHash $fixture) -cne $liveBeforeSkippedModes) { throw 'Tower Check/Backup changed disposable live or recovery data.' }
    if ((TreeHash (Join-Path $root 'apps')) -cne $repoAppsBeforeTower) { throw 'Tower modes changed repository templates.' }

    $before = TreeHash $snapshot
    $repoBefore = TreeHash (Join-Path $root 'apps')
    $liveBefore = TreeHash $fixture
    foreach ($mode in @('Backup','Check')) {
        & (Join-Path $root 'scripts/sync-windows-apps.ps1') -Mode $mode -Apply -RoamingRoot $env:APPDATA -SnapshotRoot $snapshot -BackupRoot (Join-Path $fixture 'backups')
        & (Join-Path $root 'scripts/sync-windows-extra-apps.ps1') -Mode $mode -Apply -RoamingRoot $env:APPDATA -LocalRoot $env:LOCALAPPDATA -UserRoot $fixture -RegistryRoot 'HKCU:\Software\DotfilesPublicFixtureAbsent' -SnapshotRoot (Join-Path $snapshot 'extra') -BackupRoot $extraBackupRoot
    }
    # The wrapper has no root overrides: preview its dispatch only. Apply-mode
    # policy checks above pass explicit disposable snapshot and recovery roots.
    & (Join-Path $root 'scripts/backup-apps-windows.ps1')
    if ((TreeHash $snapshot) -cne $before) { throw 'Public fixture templates changed.' }
    if ((TreeHash (Join-Path $root 'apps')) -cne $repoBefore) { throw 'Public repository templates changed.' }
    if ((TreeHash $fixture) -cne $liveBefore) { throw 'Dummy live preferences changed.' }
    Write-Output 'PASS: public backup preserves templates; shared Zed restores/checks; Tower is restore-only.'
} finally {
    $env:APPDATA = $savedRoaming
    $env:LOCALAPPDATA = $savedLocal
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
