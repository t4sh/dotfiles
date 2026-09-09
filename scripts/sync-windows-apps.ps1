#Requires -Version 7.0
[CmdletBinding()]
param([ValidateSet('Backup','Restore','Check')][string]$Mode='Check', [switch]$Apply,
    [string]$RoamingRoot=$env:APPDATA,
    [string]$SnapshotRoot=(Join-Path (Split-Path $PSScriptRoot) 'apps\windows'),
    [string]$BackupRoot=(Join-Path $HOME ('.dotfiles-backup\windows-apps-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'lib\windows-apps.ps1')
. (Join-Path $PSScriptRoot 'lib\windows-common.ps1')
Assert-DotfilesWindows
# Public snapshots are curated; never replace them with this machine's settings.
if ($Mode -in @('Backup','Check')) { Write-Output "Public templates retained; live preference $Mode is intentionally skipped."; return }
$prepared=@(); $pending=@()
foreach ($mapping in (Get-DotfilesAppMappings $RoamingRoot)) {
    $snapshot=Join-Path (Join-Path $SnapshotRoot $mapping.Editor) $mapping.File
    $source=if($Mode -eq 'Backup'){$mapping.Live}else{$snapshot}
    $target=if($Mode -eq 'Backup'){$snapshot}else{$mapping.Live}
    if (-not (Test-Path -LiteralPath $source)) { $pending += "$($mapping.Editor)/$($mapping.File): missing source"; continue }
    if ($Mode -eq 'Backup') { Assert-DotfilesPreferenceFile $source }
    elseif (Test-Path -LiteralPath $target -PathType Leaf) { Assert-DotfilesPreferenceFile $target }
    try { $settings=Get-Content -LiteralPath $source -Raw | ConvertFrom-Json -AsHashtable }
    catch { throw "Invalid preference JSON for $($mapping.Editor)/$($mapping.File); no files published." }
    if ($settings -isnot [Collections.IDictionary]) { throw 'Expected preference object; no files published.' }
    $safe=Select-DotfilesPreferences $settings $mapping.Editor
    $safe=Convert-DotfilesPreferencePaths $safe -Restore:($Mode -ne 'Backup')
    $existing=[ordered]@{}
    if ($Mode -ne 'Backup' -and (Test-Path -LiteralPath $target)) {
        try { $existing=Get-Content -LiteralPath $target -Raw | ConvertFrom-Json -AsHashtable }
        catch { throw "Destination preferences cannot be parsed for $($mapping.Editor); preserved." }
    }
    if ($Mode -eq 'Check') {
        foreach($key in $safe.Keys) {
            if (-not $existing.Contains($key) -or (ConvertTo-Json -InputObject $existing[$key] -Depth 50 -Compress) -cne (ConvertTo-Json -InputObject $safe[$key] -Depth 50 -Compress)) { $pending += "$($mapping.Editor): preference differs: $key" }
        }
        continue
    }
    $differs = @($safe.Keys | Where-Object { -not $existing.Contains($_) -or (ConvertTo-Json -InputObject $existing[$_] -Depth 50 -Compress) -cne (ConvertTo-Json -InputObject $safe[$_] -Depth 50 -Compress) }).Count -gt 0
    if ($Mode -eq 'Restore' -and -not $differs) { continue }
    if ($Mode -eq 'Restore' -and $Apply -and (Get-Process -Name $mapping.Process -ErrorAction SilentlyContinue)) {
        $pending += "$($mapping.Editor): running; close it and retry. Host editors are never terminated."; continue
    }
    if ($Mode -eq 'Restore') { foreach($key in $safe.Keys){$existing[$key]=$safe[$key]}; $safe=$existing }
    $text=((ConvertTo-Json -InputObject $safe -Depth 50) -replace "`r`n","`n")+"`n"
    if ((Test-Path -LiteralPath $target) -and [IO.File]::ReadAllText($target) -ceq $text) { continue }
    $prepared += @{Target=$target;Text=$text}
}
if ($Mode -eq 'Check') { if($pending.Count){$pending | Write-Warning; throw 'Windows preferences have drift or missing snapshots.'}; Write-Output 'Windows managed preferences match.'; return }
if (-not $Apply) { $prepared | ForEach-Object { "Preview $Mode : $($_.Target)" }; $pending | Write-Warning; return }
# Validate every input before publishing any file. Backups are kept outside the repository.
$published=@()
try {
    foreach($item in $prepared){
        $parent=Split-Path $item.Target -Parent
        [IO.Directory]::CreateDirectory($parent) | Out-Null
        $stage=Join-Path $parent ('.dotfiles-app-'+[guid]::NewGuid().ToString('N'))
        $backup=$null
        if(Test-Path -LiteralPath $item.Target){
            [IO.Directory]::CreateDirectory($backupRoot) | Out-Null
            $backup=Join-Path $backupRoot ([guid]::NewGuid().ToString('N'))
            Copy-Item -LiteralPath $item.Target -Destination $backup
        }
        try {
            Write-DotfilesText $stage $item.Text
            Move-Item -LiteralPath $stage -Destination $item.Target -Force
            $published += @{Target=$item.Target;Backup=$backup}
        } finally { if(Test-Path -LiteralPath $stage){ Remove-Item -LiteralPath $stage } }
    }
} catch {
    $originalError=$_
    $rollbackFailures=[Collections.Generic.List[string]]::new()
    [array]::Reverse($published)
    foreach($item in $published){
        try {
            if($item.Backup){Copy-Item -LiteralPath $item.Backup -Destination $item.Target -Force}
            elseif(Test-Path -LiteralPath $item.Target){Remove-Item -LiteralPath $item.Target}
        } catch {
            $recovery=if($item.Backup){$item.Backup}else{'none; newly created destination requires removal'}
            $rollbackFailures.Add("target: $($item.Target); recovery: $recovery; error: $($_.Exception.Message)")
        }
    }
    if($rollbackFailures.Count){throw [InvalidOperationException]::new("Publication failed; rollback incomplete for: $($rollbackFailures -join '; '). Original error: $($originalError.Exception.Message)",$originalError.Exception)}
    throw $originalError
}
Write-Output "$Mode published $($prepared.Count) Windows preference file(s). Mac snapshots unchanged."
if($pending.Count){$pending | Write-Warning; throw 'Some editor surfaces were deferred; retry after resolving them.'}
