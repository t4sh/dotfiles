function Get-DotfilesAppGroups {
    param([string]$Root = (Split-Path (Split-Path $PSScriptRoot)), [string]$AppGroups = 'all')
    $manifest = Join-Path $Root 'config\app-groups.tsv'
    $header = (Get-Content -LiteralPath $manifest -TotalCount 1)
    if ($header -cne "Key`tGroup") { throw 'Invalid app-groups.tsv header; expected Key and Group.' }
    $rows = @(Import-Csv -LiteralPath $manifest -Delimiter "`t")
    $known = @('essentials','development','design','ai','media','browsers','productivity','utilities')
    $declared = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($line in Get-Content -LiteralPath (Join-Path $Root 'Brewfile')) {
        if ($line -cmatch '^\s*cask "([^"]+)"' -and -not $Matches[1].StartsWith('font-')) {
            if (-not $declared.Add('cask:' + $Matches[1])) { throw "Duplicate Brewfile cask: $($Matches[1])" }
        }
    }
    $byKey = @{}
    foreach ($row in $rows) {
        if (-not $row.Key -or -not $row.Group -or $row.Group -cnotin $known) { throw "Invalid app group row: $($row.Key)" }
        if ($byKey.ContainsKey($row.Key)) { throw "Duplicate app group key: $($row.Key)" }
        if (-not $declared.Contains($row.Key)) { throw "Stale app group key: $($row.Key)" }
        $byKey[$row.Key] = $row.Group
    }
    foreach ($key in $declared) {
        if (-not $byKey.ContainsKey($key)) { throw "Missing app group key: $key" }
    }
    if ([string]::IsNullOrWhiteSpace($AppGroups)) { throw 'App groups cannot be empty; use all or none.' }
    $chosen = @($AppGroups.Split(',') | ForEach-Object { $_.Trim() })
    if (@($chosen | Where-Object { -not $_ }).Count -or @($chosen | Select-Object -Unique).Count -ne $chosen.Count) { throw 'Invalid or duplicate app group selection.' }
    if (@($chosen | Where-Object { $_ -cnotin ($known + @('fonts','all','none')) }).Count) { throw "Unknown app group selection: $AppGroups" }
    if ($chosen.Count -gt 1 -and @($chosen | Where-Object { $_ -in @('all','none') }).Count) { throw 'all and none must be selected alone.' }
    if ($chosen[0] -notin @('all','none') -and 'essentials' -notin $chosen) { $chosen += 'essentials' }
    $selected = @($rows | Where-Object { $chosen[0] -eq 'all' -or $_.Group -in $chosen } | Select-Object -ExpandProperty Key)
    if ($chosen[0] -eq 'none') { $selected = @() }
    return [pscustomobject]@{
        Groups = $chosen
        Rows = $rows
        SelectedKeys = $selected
        DeferredKeys = @($rows | Where-Object { $_.Key -notin $selected } | Select-Object -ExpandProperty Key)
    }
}

function Select-DotfilesWindowsPackages {
    param([object[]]$Rows, [object]$Selection)
    # Partial Windows app selections defer App Store counterparts, then dedupe
    # shared Windows IDs only after the selected source rows are known.
    return @($Rows |
        Where-Object {
            (-not $_.Key.StartsWith('cask:') -or $_.Key -in $Selection.SelectedKeys) -and
            (-not $_.Key.StartsWith('mas:') -or 'all' -in $Selection.Groups)
        } |
        Where-Object Mode -In @('native','runtime') |
        Sort-Object Source,Id -Unique)
}
