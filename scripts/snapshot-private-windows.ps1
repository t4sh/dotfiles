#Requires -Version 7.0
<#
Create a private, UNENCRYPTED local reference snapshot; never restore or prune.
Preview by default. Sources remain untouched, including standalone credentials.
The fixed manifest is deliberately separate from non-secret repo backup commands.
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$ProfileRoot = [Environment]::GetFolderPath('UserProfile'),
    [string]$OutputRoot,
    [switch]$PassThru
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This snapshot command requires native Windows PowerShell 7.' }
$repo = Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/lib/windows-common.ps1')
Assert-DotfilesWindows
$profilePath = [IO.Path]::GetFullPath($ProfileRoot)
function Assert-LocalSnapshotPath([string]$Path) {
    $probe = [IO.Path]::GetFullPath($Path)
    while ($probe -and -not (Test-Path -LiteralPath $probe)) { $probe = Split-Path $probe -Parent }
    if (-not $probe) { throw 'Private snapshot path has no accessible ancestor.' }
    while ($probe) {
        $ancestor = Get-Item -LiteralPath $probe -Force
        if ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Private snapshot path has a reparse-point ancestor: $probe" }
        if ($ancestor.PSIsContainer -and (Test-Path -LiteralPath (Join-Path $probe '.git'))) { throw 'Private snapshots cannot be stored inside Git.' }
        $probe = Split-Path $probe -Parent
    }
    foreach ($cloud in @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial)) {
        if ($cloud -and ($Path.TrimEnd('\') + '\').StartsWith(([IO.Path]::GetFullPath($cloud).TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Private plaintext snapshots must not be placed in OneDrive.'
        }
    }
}
Assert-LocalSnapshotPath $profilePath
$device = $env:COMPUTERNAME
if ($device -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Unsupported computer name for snapshot namespace.' }
$entries = @(Import-Csv -LiteralPath (Join-Path $repo 'config/windows-private-backup.tsv') -Delimiter "`t")
$files = [Collections.Generic.List[object]]::new()
$directories = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$omitted = [Collections.Generic.List[string]]::new()
foreach ($entry in $entries) {
    if ($entry.source -match '(^[/\\]|:|(^|[/\\])\.\.([/\\]|$))' -or $entry.payload -notmatch '^(secrets|user)(/[a-zA-Z0-9_.-]+)*$' -or ($entry.payload.Split('/') | Where-Object { $_ -in @('.','..') })) { throw 'Invalid private backup manifest path.' }
    $source = Resolve-DotfilesPrivateSource $profilePath $entry.source
    Assert-LocalSnapshotPath $source
    if (-not (Test-Path -LiteralPath $source)) {
        if ($entry.required -eq 'true') { throw "Required source missing: $($entry.source)" }
        $omitted.Add($entry.source); continue
    }
    $parts = $entry.payload.Split('/', 2)
    $target = "payload/$($parts[0])/windows/$device"
    if ($parts.Count -gt 1) { $target += '/' + $parts[1] }
    $item = Get-Item -LiteralPath $source -Force
    if ($entry.source.StartsWith('@Roaming/') -and -not $item.PSIsContainer) { Assert-DotfilesPreferenceFile $source }
    $items = @($item)
    if ($item.PSIsContainer) { $items += @(Get-ChildItem -LiteralPath $source -Force -Recurse) }
    foreach ($child in $items) {
        if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Source contains a link; explicit capture policy required: $($entry.source)" }
        $relative = if ($child.FullName -eq $item.FullName) { '' } else { '/' + [IO.Path]::GetRelativePath($source, $child.FullName).Replace('\','/') }
        $destination = $target + $relative
        if ($child.PSIsContainer) { [void]$directories.Add($destination); continue }
        $files.Add([pscustomobject]@{ Source=$child.FullName; Origin=$entry.source+$relative; Path=$destination; Bytes=$child.Length })
    }
}
if (@($files.Path | Sort-Object -Unique).Count -ne $files.Count) { throw 'Duplicate payload destinations.' }
$backupRoot = if ($OutputRoot) { [IO.Path]::GetFullPath($OutputRoot) } else { Join-Path $profilePath '.secrets-backups' }
Assert-LocalSnapshotPath $backupRoot
foreach ($entry in $entries) {
    $source = [IO.Path]::GetFullPath((Resolve-DotfilesPrivateSource $profilePath $entry.source)).TrimEnd('\')
    if (($backupRoot + '\').StartsWith($source + '\', [StringComparison]::OrdinalIgnoreCase) -or ($source + '\').StartsWith($backupRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Snapshot output must not overlap a source.' }
}
if (Test-Path -LiteralPath $backupRoot) {
    $rootItem = Get-Item -LiteralPath $backupRoot -Force
    if (-not $rootItem.PSIsContainer -or ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Backup root must be a real directory.' }
    if (Test-Path -LiteralPath (Join-Path $backupRoot '.git')) { throw 'Private snapshots cannot be stored inside Git.' }
}
Write-Host "Private snapshot: $($files.Count) files; $($omitted.Count) optional sources absent. UNENCRYPTED, local only."
if (-not $Apply) { Write-Host 'Preview only. Use -Apply to create a new snapshot; no existing files are changed.'; return }
if (-not (Test-Path -LiteralPath $backupRoot)) { [void][IO.Directory]::CreateDirectory($backupRoot) }
# Every snapshot receives a fresh protected ACL before any secret bytes are copied.
$id = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$snapshot = Join-Path $backupRoot $id
[void][IO.Directory]::CreateDirectory($snapshot)
$acl = [Security.AccessControl.DirectorySecurity]::new()
$acl.SetAccessRuleProtection($true, $false)
$owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
$acl.SetOwner($owner)
foreach ($sid in @($owner, [Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
    $rule = [Security.AccessControl.FileSystemAccessRule]::new($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    $acl.AddAccessRule($rule)
}
Set-Acl -LiteralPath $snapshot -AclObject $acl
$inventory = [Collections.Generic.List[object]]::new()
foreach ($directory in $directories) { [void][IO.Directory]::CreateDirectory((Join-Path $snapshot $directory)) }
foreach ($file in $files) {
    $destination = Join-Path $snapshot $file.Path
    [void][IO.Directory]::CreateDirectory((Split-Path $destination -Parent))
    $before = (Get-FileHash -LiteralPath $file.Source -Algorithm SHA256).Hash
    [IO.File]::Copy($file.Source, $destination, $false)
    $copied = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    $after = (Get-FileHash -LiteralPath $file.Source -Algorithm SHA256).Hash
    if ($before -ne $copied -or $before -ne $after) { throw 'Source changed or copy verification failed; snapshot is incomplete, not eligible for restore.' }
    $inventory.Add([pscustomobject]@{ Origin=$file.Origin; Path=$file.Path; Bytes=(Get-Item -LiteralPath $destination).Length; SHA256=$copied })
}
$manifest = [ordered]@{
    schema='dotfiles-reference-1'; createdUtc=[DateTime]::UtcNow.ToString('o'); platform='windows'; device=$device
    encrypted=$false; capture='file bytes; not an application-consistent or filesystem-metadata backup'
    canonicalProvenance='Source files are captured as-is; platform compatibility requires explicit recovery validation.'
    restore='Manual explicit selection only. Never feed this namespaced payload into legacy Mac secrets-restore.'
    omitted=$omitted.ToArray(); directories=@($directories | Sort-Object); files=$inventory.ToArray()
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $snapshot 'manifest.json') -Encoding utf8NoBOM
[IO.File]::WriteAllText((Join-Path $snapshot 'COMPLETE'), 'All declared file copies hash-verified. Local plaintext reference only.' + "`n", [Text.UTF8Encoding]::new($false))
Write-Host "COMPLETE: $snapshot"
if ($PassThru) { Write-Output $snapshot }
