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
    $file = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-inventory-'+[guid]::NewGuid().ToString('N')+'.json')
    try {
        & winget.exe export --output $file --include-versions --accept-source-agreements --disable-interactivity *> $null
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
            & winget.exe list --id $package.Id --exact --source msstore --accept-source-agreements --disable-interactivity *> $null
            $code=$LASTEXITCODE
            if ($code -eq 0) { $result[$key]='Installed; version omitted from export' }
            elseif ($code -ne -1978335212) { throw "WinGet Store inventory failed for $($package.Id) (exit $code)" }
        }
        return $result
    } finally { if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file } }
}
