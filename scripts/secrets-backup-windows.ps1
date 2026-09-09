#Requires -Version 7.4
<#
Native tar.age backup. Preview by default; never restores over live files.
InitializeKey -> independently save the key -> ConfirmRecovery -> Backup.
Check decrypts/authenticates a whole archive in private temporary storage.
Open authenticates and extracts a protected local view; Close removes that view.
#>
[CmdletBinding()]
param(
    [ValidateSet('Backup','InitializeKey','ConfirmRecovery','Check','Open','Close')][string]$Action = 'Backup',
    [switch]$Apply,
    [string]$Archive,
    [string]$View,
    [switch]$NoExplorer,
    [string]$Destination,
    [switch]$NonInteractive,
    [string]$ProfileRoot = [Environment]::GetFolderPath('UserProfile')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/windows-common.ps1')
. (Join-Path $PSScriptRoot 'lib/windows-vault-destination.ps1')
. (Join-Path $PSScriptRoot 'lib/windows-vault-view.ps1')
Assert-DotfilesWindows
$profilePath = [IO.Path]::GetFullPath($ProfileRoot)
$keyRoot = Join-Path $profilePath '.secrets-keys'
$key = Join-Path $keyRoot 'windows-backup.agekey'
$ack = Join-Path $keyRoot 'windows-backup.recovery-confirmed'
$backupRoot = Join-Path $profilePath '.secrets-backups'
$localState = Join-Path $profilePath '.dotfiles-local'
$destinationCache = Join-Path $localState 'backup-windows.destination'
function Assert-PrivatePath([string]$Path, [switch]$AllowCloud) {
    $probe = $Path
    while ($probe -and -not (Test-Path -LiteralPath $probe)) { $probe = Split-Path $probe -Parent }
    if (-not $probe) { throw 'Private path has no accessible ancestor.' }
    while ($probe) {
        $ancestor = Get-Item -LiteralPath $probe -Force
        if ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            if (-not ($AllowCloud -and $ancestor.PSIsContainer -and (Test-WindowsVaultCloudDirectory $probe))) {
                throw "Private path has an unsupported reparse point at '$probe'. Only verified cloud-placeholder directories are allowed for encrypted output; keys and staging require ordinary local paths."
            }
        }
        if ($ancestor.PSIsContainer -and (Test-Path -LiteralPath (Join-Path $probe '.git'))) { throw 'Private vault state cannot be stored inside Git.' }
        $probe = Split-Path $probe -Parent
    }
    foreach ($cloud in @($env:OneDrive,$env:OneDriveConsumer,$env:OneDriveCommercial)) {
        if (-not $AllowCloud -and $cloud -and ($Path.TrimEnd('\')+'\').StartsWith(([IO.Path]::GetFullPath($cloud).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)) { throw 'Local vault keys and staging must not be in OneDrive.' }
    }
}
function New-PrivateDirectory([string]$Path) {
    Assert-PrivatePath $Path
    if (Test-Path -LiteralPath $Path) { throw 'Refusing to replace an existing private directory.' }
    [void][IO.Directory]::CreateDirectory($Path)
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true,$false)
    $owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl.SetOwner($owner)
    foreach ($sid in @($owner,[Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}
function Resolve-AgeTool([string]$Name) {
    $command = Get-Command ($Name+'.exe') -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $link = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) "Microsoft/WinGet/Links/$Name.exe"
    if (Test-Path -LiteralPath $link) { return $link }
    throw 'age is missing. Install: winget install --id FiloSottile.age --exact --source winget'
}
function Assert-KeyAcl {
    $allowed = @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value,'S-1-5-18')
    $sandboxSid = $null
    try { $sandboxSid = ([Security.Principal.NTAccount]::new($env:COMPUTERNAME,'CodexSandboxUsers')).Translate([Security.Principal.SecurityIdentifier]).Value }
    catch [Security.Principal.IdentityNotMappedException] { } # No group means no exception.
    $readOnlyMask = [int][Security.AccessControl.FileSystemRights]::ReadAndExecute -bor [int][Security.AccessControl.FileSystemRights]::Synchronize
    $sandboxRead = $false
    # A safe file ACL alone cannot prevent replacement through a writable parent.
    $rules = foreach ($aclPath in @((Split-Path $key -Parent),$key)) { (Get-Acl -LiteralPath $aclPath).GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]) }
    foreach ($rule in $rules) {
        if ($rule.AccessControlType -ne 'Allow' -or $rule.IdentityReference.Value -in $allowed) { continue }
        # Operator-approved exception: exact local group, read-only rights only.
        if ($sandboxSid -and $rule.IdentityReference.Value -eq $sandboxSid -and (([int]$rule.FileSystemRights -band (-bnot $readOnlyMask)) -eq 0)) {
            $sandboxRead = $true
            continue
        }
        throw 'Recovery key ACL permits another identity; inspect its Windows permissions before use.'
    }
    if ($sandboxRead) { Write-Warning 'Recovery key is readable by local CodexSandboxUsers (operator-approved read-only exception). Group write/delete/permission changes are not permitted.' }
}
Assert-PrivatePath $keyRoot
Assert-PrivatePath $backupRoot
if ($Action -eq 'Close') {
    if (-not $View) { throw 'Specify -View with the exact folder printed by secrets-open.' }
    if (-not $Apply) { Write-Host 'Preview: close the specified secret view; use -Apply to delete its temporary plaintext.'; return }
    Remove-WindowsVaultView $View $backupRoot
    Write-Host 'Secret view removed. Encrypted archives and live secrets unchanged.'
    return
}
if ($Action -eq 'Open') {
    if (-not $Archive) {
        if (-not (Test-Path -LiteralPath $destinationCache -PathType Leaf)) { throw 'Specify -Archive, or first save a backup destination.' }
        $saved = [IO.File]::ReadAllText($destinationCache).Trim()
        $latest = Get-ChildItem -LiteralPath $saved -Filter 'DotfilesSecrets-windows-*.tar.age' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $latest) { throw 'No completed archive in the saved destination; specify -Archive.' }
        $Archive = $latest.FullName
    }
    if (-not (Test-Path -LiteralPath $Archive -PathType Leaf)) { throw 'Archive not found.' }
    Write-Host "Selected encrypted archive: $Archive"
}
if ($Action -eq 'Backup') {
    Assert-PrivatePath $destinationCache
    $savedDestination = if (Test-Path -LiteralPath $destinationCache -PathType Leaf) { [IO.File]::ReadAllText($destinationCache).Trim() } else { '' }
    if (-not $NonInteractive -and [Console]::IsInputRedirected) { throw 'An interactive destination prompt is required. Use -NonInteractive with a saved or explicit -Destination for unattended runs.' }
    $publishRoot = Select-WindowsVaultDestination -Destination $Destination -SavedDestination $savedDestination -NonInteractive:$NonInteractive
    Assert-PrivatePath $publishRoot -AllowCloud
    # Encrypted output can use an external/cloud folder, but never a source or key tree.
    $sources = @(Import-Csv -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'config/windows-private-backup.tsv') -Delimiter "`t" | ForEach-Object { Resolve-DotfilesPrivateSource $profilePath $_.source })
    foreach ($source in @($sources) + @($keyRoot,$localState)) {
        $sourcePrefix = [IO.Path]::GetFullPath($source).TrimEnd('\')+'\'
        if (($publishRoot.TrimEnd('\')+'\').StartsWith($sourcePrefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Encrypted destination must not be inside a captured source, key directory or local-state directory.' }
    }
    if ($Apply) {
        if (-not (Test-Path -LiteralPath $localState)) { New-PrivateDirectory $localState }
        [IO.File]::WriteAllText($destinationCache,$publishRoot+"`n",[Text.UTF8Encoding]::new($false))
        Write-Host "Destination remembered in $destinationCache"
    }
}
if (-not $Apply) {
    Write-Host "Preview: $Action; native tar.age; private key outside payload; all retained backups untouched."
    if ($Action -eq 'Backup') { & (Join-Path $PSScriptRoot 'snapshot-private-windows.ps1') -ProfileRoot $profilePath }
    return
}
$age = Resolve-AgeTool 'age'
$keygen = Resolve-AgeTool 'age-keygen'
if ($Action -eq 'InitializeKey') {
    if (Test-Path -LiteralPath $key) { Assert-PrivatePath $key; Assert-KeyAcl; Write-Host 'Recovery key already exists; preserved unchanged.'; return }
    if (Test-Path -LiteralPath $keyRoot) { throw 'Key directory already exists without the expected key; inspect it before initialization.' }
    New-PrivateDirectory $keyRoot
    Invoke-DotfilesNative $keygen @('-o',$key)
    Assert-KeyAcl
    Write-Host 'Verified Windows key ACL: current account/SYSTEM; only the approved read-only local sandbox-group exception is permitted.'
    Write-Host "Key created at $key. Save an independent copy securely, then run ConfirmRecovery. Never paste it into chat."
    return
}
if (-not (Test-Path -LiteralPath $key -PathType Leaf)) { throw 'Recovery key missing. Run -Action InitializeKey -Apply first.' }
Assert-PrivatePath $key
Assert-KeyAcl
$recipient = @(& $keygen -y $key)
if ($LASTEXITCODE -ne 0 -or $recipient.Count -ne 1 -or $recipient[0] -notmatch '^age1[0-9a-z]+$') { throw 'Unable to derive the expected age recipient.' }
if ($Action -eq 'ConfirmRecovery') {
    # Operator attestation only, never called automatically by setup or backup.
    Assert-PrivatePath $ack
    [IO.File]::WriteAllText($ack,$recipient[0]+"`n",[Text.UTF8Encoding]::new($false))
    Write-Host 'Independent recovery-copy confirmation recorded for this key.'
    return
}
Assert-PrivatePath $ack
if ($Action -eq 'Backup' -and (-not (Test-Path -LiteralPath $ack) -or [IO.File]::ReadAllText($ack).Trim() -cne $recipient[0])) {
    throw 'Independent recovery copy is not confirmed. Save the key outside this PC, then run -Action ConfirmRecovery -Apply.'
}
if ($Action -eq 'Check' -and (-not $Archive -or -not (Test-Path -LiteralPath $Archive -PathType Leaf))) { throw 'Check requires -Archive pointing to a tar.age file.' }
$tar = Join-Path $env:WINDIR 'System32/tar.exe'
if (-not (Test-Path -LiteralPath $tar)) { throw 'Native Windows tar.exe is missing.' }
if (-not (Test-Path -LiteralPath $backupRoot)) { New-PrivateDirectory $backupRoot }
$work = Join-Path $backupRoot ('.work-'+[Guid]::NewGuid().ToString('N'))
New-PrivateDirectory $work
$plainTar = Join-Path $work 'payload.tar'
$verifiedTar = Join-Path $work 'verified.tar'
$publicationPartial = $null
$backupFailure = $null
$stage = 'capture/authentication'
try {
    if ($Action -in @('Check','Open')) {
        Invoke-DotfilesNative $age @('--decrypt','-i',$key,'-o',$verifiedTar,[IO.Path]::GetFullPath($Archive))
        if ($Action -eq 'Open') {
            $viewPath = Join-Path $backupRoot ('view-'+[Guid]::NewGuid().ToString('N'))
            New-PrivateDirectory $viewPath
            try {
                [IO.File]::WriteAllText((Join-Path $viewPath '.dotfiles-view'),'dotfiles-windows-vault-view-v1')
                $content = Join-Path $viewPath 'files'
                Expand-WindowsVaultTar $verifiedTar $content
            } catch {
                try { Remove-WindowsVaultView $viewPath $backupRoot }
                catch { Write-Warning "Incomplete plaintext view retained at '$viewPath'; close it after resolving the cleanup failure." }
                throw 'Secret view could not be extracted safely; archive contents withheld.'
            }
            Write-Host "OPEN: $viewPath"
            Write-Host "Temporary plaintext; close when finished: dot secrets-close -View '$viewPath' -Apply"
            if (-not $NoExplorer) {
                try { Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList ('"'+$content+'"') -WindowStyle Hidden | Out-Null }
                catch { Write-Warning "Explorer could not open; the verified view remains at '$viewPath'." }
            }
            return
        }
        $null = & $tar -tf $verifiedTar
        if ($LASTEXITCODE -ne 0) { throw 'Authenticated content is not a readable tar archive.' }
        Write-Host 'PASS: full age authentication and tar readability. No files restored to live locations.'
        return
    }
    $snapshot = & (Join-Path $PSScriptRoot 'snapshot-private-windows.ps1') -ProfileRoot $profilePath -OutputRoot (Join-Path $work 'capture') -Apply -PassThru
    if (-not (Test-Path -LiteralPath (Join-Path $snapshot 'COMPLETE'))) { throw 'Capture did not complete.' }
    $manifestPath = Join-Path $snapshot 'manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifest.encrypted = $true # Describes the published outer archive, not transient staging.
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
    Invoke-DotfilesNative $tar @('-cf',$plainTar,'-C',$snapshot,'manifest.json','COMPLETE','payload')
    $cipher = Join-Path $work 'payload.tar.age'
    Invoke-DotfilesNative $age @('--encrypt','-r',$recipient[0],'-o',$cipher,$plainTar)
    Invoke-DotfilesNative $age @('--decrypt','-i',$key,'-o',$verifiedTar,$cipher)
    if ((Get-FileHash -LiteralPath $plainTar).Hash -ne (Get-FileHash -LiteralPath $verifiedTar).Hash) { throw 'Encrypted round-trip digest mismatch.' }
    $name = 'DotfilesSecrets-windows-'+(Split-Path $snapshot -Leaf)+'.tar.age'
    Assert-PrivatePath $publishRoot -AllowCloud
    $final = Join-Path $publishRoot $name
    # Copy then rename within the destination volume; supports removable/network drives.
    $candidate = Join-Path $publishRoot ('.'+$name+'.partial-'+[Guid]::NewGuid().ToString('N'))
    $stage = 'copy encrypted archive to destination'
    $outputStream = [IO.File]::Open($candidate,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $publicationPartial = $candidate
    try {
        $inputStream = [IO.File]::OpenRead($cipher)
        try { $inputStream.CopyTo($outputStream); $outputStream.Flush($true) } finally { $inputStream.Dispose() }
    } finally { $outputStream.Dispose() }
    $stage = 'verify destination ciphertext'
    $publishedHash = Invoke-WindowsVaultFileOperation -Description $stage -Operation { (Get-FileHash -LiteralPath $publicationPartial -ErrorAction Stop).Hash }
    if ((Get-FileHash -LiteralPath $cipher).Hash -ne $publishedHash) { throw 'Published ciphertext copy failed hash verification.' }
    $stage = 'rename verified encrypted archive'
    Invoke-WindowsVaultFileOperation -Description $stage -Operation { [IO.File]::Move($publicationPartial,$final,$false) }
    $publicationPartial = $null
    Write-Host "COMPLETE: $final"
    Write-Host 'Encrypted archive locally round-trip verified; no previous snapshots or live credentials changed.'
} catch {
    $backupFailure = $_
    Write-Warning "Backup failed during '$stage': $($_.Exception.Message)"
    throw
} finally {
    if ($publicationPartial -and (Test-Path -LiteralPath $publicationPartial)) {
        try { [IO.File]::Delete($publicationPartial) }
        catch { Write-Warning "Encrypted partial retained at '$publicationPartial'; cleanup failed: $($_.Exception.Message)" }
    }
    try {
        # Delete only this invocation's explicit private staging directory, never retained backups.
        $resolved = [IO.Path]::GetFullPath($work)
        $expectedParent = [IO.Path]::GetFullPath($backupRoot).TrimEnd('\')
        if ((Split-Path $resolved -Parent) -cne $expectedParent -or (Split-Path $resolved -Leaf) -notmatch '^\.work-[0-9a-f]{32}$') { throw 'Unsafe temporary cleanup path; preserved for inspection.' }
        Assert-PrivatePath $resolved
        if (@(Get-ChildItem -LiteralPath $resolved -Recurse -Force -Attributes ReparsePoint).Count) { throw 'Unexpected staging link; directory preserved for inspection.' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    } catch {
        Write-Warning "Local plaintext staging retained at '$work'; cleanup failed: $($_.Exception.Message)"
        if (-not $backupFailure) { throw }
    }
}
