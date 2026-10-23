function Set-DotfilesDeskflowStablePin([string]$Version) {
    # WinGet compares the pin itself; its display table also includes the installed version.
    & winget.exe pin add --id Deskflow.Deskflow --exact --source winget --version $Version --force --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) { throw "WinGet could not pin Deskflow to stable $Version (exit $LASTEXITCODE)" }
}
function Get-DotfilesListedWinGetVersions([string[]]$Lines) {
    $found=[Collections.Generic.List[string]]::new()
    foreach($line in $Lines){
        $entry=$line.Trim()
        if($entry -cmatch '^\d+\.\d+\.\d+(?:\.\d+)?$'){ $found.Add($entry) }
    }
    return $found
}
function Test-DotfilesStableWinGetVersion([string]$Version) {
    # Continuous Deskflow builds add a fourth component, such as 1.27.0.10.
    return $Version -cmatch '^\d+\.\d+\.\d+$'
}
function Get-DotfilesLatestStableWinGetVersion([string[]]$Versions) {
    $stable=@($Versions | Where-Object { Test-DotfilesStableWinGetVersion $_ })
    if(-not $stable.Count){ return '' }
    return [string]@($stable | Sort-Object @{Expression={[version]$_}} -Descending)[0]
}
function Get-DotfilesDeskflowBlockedVersions {
    # Smart App Control blocks unsigned Deskflow 1.27.0: the binaries have no
    # reputation, and Code Integrity events 3033/3077 deny deskflow.exe.
    # 1.26.0 is the newest stable build that launches with protection left on.
    return @('1.27.0')
}
function Get-DotfilesInstallableDeskflowVersion([string[]]$Versions) {
    $blocked=@(Get-DotfilesDeskflowBlockedVersions)
    $allowed=@($Versions | Where-Object { $_ -notin $blocked })
    return Get-DotfilesLatestStableWinGetVersion $allowed
}
function Test-DotfilesDeskflowRequiresReplacement([string]$Installed,[string]$Target) {
    if(-not $Installed -or $Installed -ceq $Target){ return $false }
    if(Test-DotfilesStableWinGetVersion $Installed){
        return [version]$Installed -gt [version]$Target
    }
    return $true
}
function Convert-DotfilesInstalledWinGetVersion([string]$Version) {
    # The stable MSI reports 1.27.0 as 1.27.0.0. A non-zero fourth component stays continuous.
    if($Version -cmatch '^(\d+\.\d+\.\d+)\.0$'){ return $Matches[1] }
    return $Version
}
function Get-DotfilesWindowsPackages {
    param([string]$Root = (Split-Path (Split-Path $PSScriptRoot)))
    $rows = @(Import-Csv -LiteralPath (Join-Path $Root 'config\windows-packages.tsv') -Delimiter "`t")
    $seen = @{}
    foreach ($row in $rows) {
        if ($seen.ContainsKey($row.Key)) { throw "Duplicate Windows mapping: $($row.Key)" }
        if ($row.Mode -notin @('native','runtime','manual','excluded','macos-only') -or -not $row.Note) { throw "Invalid Windows mapping: $($row.Key)" }
        if ($row.Mode -eq 'native' -and ($row.Source -notin @('winget','msstore') -or -not $row.Id)) { throw "Invalid native package: $($row.Key)" }
        if ($row.Mode -eq 'runtime' -and ($row.Source -notin @('uv','volta') -or -not $row.Id)) { throw "Invalid runtime package: $($row.Key)" }
        $seen[$row.Key] = $row
    }
    $declared = @{}
    foreach ($line in Get-Content -LiteralPath (Join-Path $Root 'Brewfile')) {
        if ($line -notmatch '^(tap|brew|cask|mas|npm|uv|vscode) "([^"]+)"(?:, id: ([0-9]+))?') { continue }
        $kind=$matches[1]; $name=$matches[2]; $id=$matches[3]
        if ($kind -eq 'vscode' -or ($kind -eq 'cask' -and $name.StartsWith('font-'))) { continue }
        $key = $kind + ':' + $(if ($kind -eq 'mas') {$id} else {$name})
        $declared[$key] = $true
        if (-not $seen.ContainsKey($key)) { throw "Unmapped Brewfile entry: $key. Add a Windows mapping or explicit disposition." }
    }
    foreach ($row in $rows) {
        if (-not $declared.ContainsKey($row.Key) -and -not $row.Key.StartsWith('windows:')) { throw "Stale Windows mapping: $($row.Key)" }
    }
    return $rows
}
function Get-DotfilesWindowsInventory {
    param([switch]$ReadOnly)
    $file = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-inventory-'+[guid]::NewGuid().ToString('N')+'.json')
    try {
        $agreementArgs = if ($ReadOnly) { @() } else { @('--accept-source-agreements') }
        & winget.exe export --output $file --include-versions @agreementArgs --disable-interactivity *> $null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $file)) { throw "WinGet inventory failed (exit $LASTEXITCODE)" }
        $inventory = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
        $result = @{}
        foreach ($source in $inventory.Sources) {
            foreach ($package in $source.Packages) { $result[$source.SourceDetails.Name+':'+$package.PackageIdentifier] = $package.Version }
        }
        # Export can omit a Store app that exact-ID `list` recognizes (Perplexity).
        # Check only declared Store IDs missing from export; never infer identity by name.
        foreach ($package in (Get-DotfilesWindowsPackages | Where-Object { $_.Mode -eq 'native' -and $_.Source -eq 'msstore' } | Sort-Object Id -Unique)) {
            $key='msstore:'+$package.Id
            if ($result.ContainsKey($key)) { continue }
            & winget.exe list --id $package.Id --exact --source msstore @agreementArgs --disable-interactivity *> $null
            $code=$LASTEXITCODE
            if ($code -eq 0) { $result[$key]='Installed; version omitted from export' }
            elseif ($code -ne -1978335212) { throw "WinGet Store inventory failed for $($package.Id) (exit $code)" }
        }
        return $result
    } finally { if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file } }
}
