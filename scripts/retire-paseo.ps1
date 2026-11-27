#Requires -Version 7.4
[CmdletBinding()]
param([switch]$Apply)

$ErrorActionPreference = 'Stop'

function ConvertTo-PaseoPathKey([string]$Path) {
    if ($null -eq $Path) { return '' }
    return $Path.Trim().TrimEnd('\','/').Replace('/','\').ToUpperInvariant()
}

function Remove-PaseoPathEntry([AllowNull()][string]$Path, [Parameter(Mandatory)][string]$LegacyPath) {
    if ($null -eq $Path) { return $null }
    $legacyKey = ConvertTo-PaseoPathKey $LegacyPath
    $kept = foreach ($entry in $Path.Split([char]';')) {
        if ((ConvertTo-PaseoPathKey $entry) -cne $legacyKey) { $entry }
    }
    return ($kept -join ';')
}

function Assert-PaseoSkillsParent([string]$HomeRoot) {
    $codex = Join-Path $HomeRoot '.codex'
    $skills = Join-Path $codex 'skills'
    foreach ($parent in @($codex,$skills)) {
        $item = Get-Item -LiteralPath $parent -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Refusing Paseo cleanup: $parent is a reparse point. Review it manually."
        }
    }
    return $skills
}

function Get-PaseoLegacyLinks([string]$HomeRoot, [string]$DotfilesRoot) {
    $skills = Assert-PaseoSkillsParent $HomeRoot
    if (-not (Test-Path -LiteralPath $skills -PathType Container)) { return @() }
    $names = @('paseo','paseo-advisor','paseo-committee','paseo-handoff','paseo-help','paseo-plugin')
    foreach ($name in $names) {
        $target = Join-Path $skills $name
        $item = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
        if (-not $item) { continue }
        if ($item.LinkType -notin @('Junction','SymbolicLink') -or
            -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
            -not ($item.Attributes -band [IO.FileAttributes]::Directory)) {
            Write-Host "Preserving non-directory-link entry: $target"
            continue
        }

        # Use the junction's recorded target, not its resolved destination. This
        # also permits identification after the retired source directory vanished.
        $recordedTarget = [string]$item.LinkTarget
        if (-not $recordedTarget) {
            Write-Host "Preserving directory link whose target cannot be read: $target"
            continue
        }
        $expected = Join-Path (Join-Path $DotfilesRoot 'agents\skills') $name
        $owned = (ConvertTo-PaseoPathKey $recordedTarget) -ceq (ConvertTo-PaseoPathKey $expected)
        if ($owned) {
            [pscustomobject]@{ Path=$target; Target=$expected }
        } else {
            Write-Host "Preserving foreign directory link: $target"
        }
    }
}

function Invoke-PaseoRetirement([string]$HomeRoot, [string]$DotfilesRoot, [AllowNull()][string]$UserPath, [switch]$Apply) {
    $skills = Assert-PaseoSkillsParent $HomeRoot
    $links = @(Get-PaseoLegacyLinks $HomeRoot $DotfilesRoot)
    foreach ($link in $links) {
        if ($Apply) {
            # Non-recursive deletion removes the directory reparse point itself;
            # never recurse into the target.
            [IO.Directory]::Delete($link.Path, $false)
            Write-Host "Removed owned directory link: $($link.Path)"
        } else {
            Write-Host "Would remove owned directory link: $($link.Path) -> $($link.Target)"
        }
    }
    if ($links.Count -eq 0) { Write-Host 'No exact former Paseo directory links found; nothing to retire.' }

    $legacyPath = Join-Path $env:LOCALAPPDATA 'Programs\Paseo\resources\bin'
    $newUserPath = Remove-PaseoPathEntry $UserPath $legacyPath
    $pathChanged = $newUserPath -cne $UserPath
    if ($pathChanged) {
        if ($Apply) { Write-Host "Will remove the known default Paseo PATH entry: $legacyPath" }
        else { Write-Host "Would remove the known default Paseo PATH entry: $legacyPath" }
    } else {
        Write-Host 'No exact known default Paseo PATH entry found.'
    }
    if (-not $Apply) { Write-Host 'Preview only. Re-run with -Apply to remove listed junctions and update User PATH.' }
    [pscustomobject]@{ UserPath=$newUserPath; PathChanged=$pathChanged; SkillsRoot=$skills }
}

if ($MyInvocation.InvocationName -ne '.') {
    . (Join-Path $PSScriptRoot 'lib\windows-common.ps1')
    Assert-DotfilesWindows
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $userRoot = [Environment]::GetFolderPath('UserProfile')
    $userPath = [Environment]::GetEnvironmentVariable('Path','User')
    $result = Invoke-PaseoRetirement -HomeRoot $userRoot -DotfilesRoot $repoRoot -UserPath $userPath -Apply:$Apply
    if ($Apply -and $result.PathChanged) {
        [Environment]::SetEnvironmentVariable('Path',$result.UserPath,'User')
        Write-Host 'Updated User PATH.'
    }
}
