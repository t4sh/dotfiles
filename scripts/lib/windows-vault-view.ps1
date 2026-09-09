#Requires -Version 7.4
# Authenticated tar input only. Never restore to live paths or honor archive links.
function Expand-WindowsVaultTar([string]$TarPath, [string]$Destination) {
    Add-Type -AssemblyName System.Formats.Tar
    if (Test-Path -LiteralPath $Destination) { throw 'Extraction destination must be new.' }
    $root = [IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'
    $entries = [Collections.Generic.Dictionary[string,bool]]::new([StringComparer]::OrdinalIgnoreCase)
    # Validate the complete archive before creating any extracted file.
    $stream = [IO.File]::OpenRead($TarPath)
    $reader = [System.Formats.Tar.TarReader]::new($stream)
    try {
        while ($entry = $reader.GetNextEntry()) {
            $directory = $entry.EntryType -eq [System.Formats.Tar.TarEntryType]::Directory
            if (-not $directory -and $entry.EntryType -notin @([System.Formats.Tar.TarEntryType]::RegularFile,[System.Formats.Tar.TarEntryType]::V7RegularFile)) { throw 'Archive links and special entries are not supported.' }
            $name = $entry.Name.TrimEnd('/')
            if (-not $name -or $name.Contains('\') -or $name.StartsWith('/')) { throw 'Unsafe archive path.' }
            foreach ($part in $name.Split('/')) {
                if (-not $part -or $part -in @('.','..') -or $part -match '[<>:"|?*\x00-\x1f]' -or $part -match '[. ]$' -or $part -match '^(?i:CON|PRN|AUX|NUL|COM[0-9¹²³]|LPT[0-9¹²³])(?:\.|$)') { throw 'Unsafe Windows archive name.' }
            }
            if ($entries.ContainsKey($name)) { throw 'Duplicate archive path.' }
            $entries.Add($name,$directory)
        }
    } finally { $reader.Dispose(); $stream.Dispose() }
    if (-not $entries.Count) { throw 'Archive is empty.' }
    foreach ($name in $entries.Keys) {
        $parent = $name
        while ($parent.Contains('/')) {
            $parent = $parent.Substring(0,$parent.LastIndexOf('/'))
            if ($entries.ContainsKey($parent) -and -not $entries[$parent]) { throw 'Archive file/directory conflict.' }
        }
    }
    [void][IO.Directory]::CreateDirectory($Destination)
    $stream = [IO.File]::OpenRead($TarPath)
    $reader = [System.Formats.Tar.TarReader]::new($stream)
    try {
        while ($entry = $reader.GetNextEntry()) {
            $target = [IO.Path]::GetFullPath((Join-Path $Destination $entry.Name.TrimEnd('/')))
            if (-not $target.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) { throw 'Archive escaped extraction directory.' }
            if ($entry.EntryType -eq [System.Formats.Tar.TarEntryType]::Directory) { [void][IO.Directory]::CreateDirectory($target); continue }
            [void][IO.Directory]::CreateDirectory((Split-Path $target))
            $output = [IO.File]::Open($target,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try { if ($entry.DataStream) { $entry.DataStream.CopyTo($output) } } finally { $output.Dispose() }
        }
    } finally { $reader.Dispose(); $stream.Dispose() }
}

function Remove-WindowsVaultView([string]$View, [string]$BackupRoot) {
    $resolved = [IO.Path]::GetFullPath($View).TrimEnd('\')
    if ((Split-Path $resolved -Parent) -ine [IO.Path]::GetFullPath($BackupRoot).TrimEnd('\') -or (Split-Path $resolved -Leaf) -cnotmatch '^view-[0-9a-f]{32}$') { throw 'Close requires an exact view folder created by secrets-open.' }
    Assert-PrivatePath $resolved
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) { throw 'View folder does not exist.' }
    if (@(Get-ChildItem -LiteralPath $resolved -Recurse -Force -Attributes ReparsePoint).Count) { throw 'View contains a link; preserved for inspection.' }
    $marker = Join-Path $resolved '.dotfiles-view'
    if (-not (Test-Path -LiteralPath $marker -PathType Leaf) -or [IO.File]::ReadAllText($marker) -cne 'dotfiles-windows-vault-view-v1') { throw 'View ownership marker missing or invalid; preserved.' }
    # Only the validated direct child of the private backup root is deleted.
    foreach ($child in Get-ChildItem -LiteralPath $resolved -Force) {
        if ($child.FullName -ine $marker) { Remove-Item -LiteralPath $child.FullName -Recurse -Force -ErrorAction Stop }
    }
    # Keep the marker until every payload item is gone, allowing a locked-file retry.
    Remove-Item -LiteralPath $marker -Force -ErrorAction Stop
    [IO.Directory]::Delete($resolved)
}
