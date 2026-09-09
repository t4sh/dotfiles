# Destination selection and narrowly scoped publication-lock handling.
function Invoke-WindowsVaultFileOperation {
    param([scriptblock]$Operation, [string]$Description, [int]$TimeoutSeconds = 30)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $announced = $false
    while ($true) {
        try { return (& $Operation) } catch {
            $exception = $_.Exception
            while ($exception.InnerException) { $exception = $exception.InnerException }
            $code = $exception.HResult -band 0xffff
            # Win32 error codes 32/33: https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--0-499-
            # ERROR_SHARING_VIOLATION / ERROR_LOCK_VIOLATION only. Never retry
            # permission errors, corruption, disk-full, or an existing final name.
            if ($code -notin @(32,33) -or $timer.Elapsed.TotalSeconds -ge $TimeoutSeconds) { throw }
            if (-not $announced) { Write-Host "Waiting for file lock: $Description (up to $TimeoutSeconds seconds)"; $announced = $true }
            # Poll the actual operation for lock release; timeout bounds this wait.
            Start-Sleep -Milliseconds 250
        }
    }
}

function Test-WindowsVaultCloudDirectory {
    param([string]$Path)
    # Read the tag, not LinkType: cloud placeholders and unknown reparse types
    # can both have an empty LinkType. Never accept an unknown tag/query failure.
    $result = @(& (Join-Path $env:WINDIR 'System32/fsutil.exe') reparsepoint query $Path 2>&1)
    if ($LASTEXITCODE -ne 0 -or $result.Count -eq 0) { return $false }
    # Match only the numeric tag on the first line, independent of localized labels.
    $tag = [regex]::Match([string]$result[0], '0x([0-9a-fA-F]{8})\s*$')
    if (-not $tag.Success) { return $false }
    # IO_REPARSE_TAG_CLOUD and CLOUD_1..F, not name-surrogate links/mount points.
    return ($tag.Groups[1].Value -match '^9000[0-9a-fA-F]01[aA]$')
}

function Select-WindowsVaultDestination {
    param([string]$Destination, [string]$SavedDestination, [switch]$NonInteractive)
    $suggested = if ($Destination) { $Destination } else { $SavedDestination }
    if ($NonInteractive) {
        if (-not $suggested) { throw 'No destination configured. Supply -Destination or choose one interactively first.' }
        $selected = $suggested
    } else {
        $label = if ($suggested) { "Encrypted backup destination [$suggested] (Enter to keep)" } else { 'Encrypted backup destination (existing folder)' }
        $reply = Read-Host $label
        if ($null -eq $reply) { throw 'No interactive input. Use -NonInteractive with a saved or explicit -Destination.' }
        $selected = if ([string]::IsNullOrWhiteSpace($reply)) { $suggested } else { $reply }
    }
    if (-not $selected) { throw 'A backup destination is required.' }
    $selected = $selected.Trim().Trim('"')
    if (-not [IO.Path]::IsPathFullyQualified($selected)) { throw 'Backup destination must be an absolute path.' }
    $selected = [IO.Path]::GetFullPath($selected)
    if (-not (Test-Path -LiteralPath $selected -PathType Container)) { throw 'Backup destination must be an existing folder; check that the drive is connected.' }
    Write-Host "Encrypted backup destination: $selected"
    return $selected
}
