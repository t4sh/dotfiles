#Requires -Version 7.4
$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot '..\scripts\retire-paseo.ps1'
. $script

function Assert-That([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "Assertion failed: $Message" }
}
function Assert-Throws([scriptblock]$Action, [string]$Message) {
    try { & $Action } catch { return }
    throw "Expected exception: $Message"
}

# Pure PATH fixture: only the known default value is filtered. Keep exact
# spelling and order for all unrelated entries, including duplicates.
$legacy = 'C:\Users\fixture\AppData\Local\Programs\Paseo\resources\bin'
$inputPath = "C:\Odd Spelling; $($legacy.ToUpperInvariant())/ ;C:\Odd Spelling;C:\Tail"
$filtered = Remove-PaseoPathEntry $inputPath $legacy
Assert-That ($filtered -ceq 'C:\Odd Spelling;C:\Odd Spelling;C:\Tail') 'PATH normalization and unrelated spelling/order'
Assert-That ((Remove-PaseoPathEntry $filtered $legacy) -ceq $filtered) 'PATH filtering is idempotent'
Assert-That ((Remove-PaseoPathEntry 'C:\Custom\Paseo\bin;C:\Tail' $legacy) -ceq 'C:\Custom\Paseo\bin;C:\Tail') 'custom Paseo PATH preserved'

$oldLocalAppData = $env:LOCALAPPDATA
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('paseo-retirement-' + [guid]::NewGuid().ToString('N'))
$repo = Join-Path $fixture 'repo'
$fixtureHome = Join-Path $fixture 'home'
$skills = Join-Path $fixtureHome '.codex\skills'
$guardHome = Join-Path $fixture 'guard-home'
$guardSkills = Join-Path $guardHome '.codex\skills'
$foreignRoot = Join-Path $fixture 'foreign'
$sourceRoot = Join-Path $repo 'agents\skills'
try {
    [IO.Directory]::CreateDirectory($skills) | Out-Null
    [IO.Directory]::CreateDirectory($foreignRoot) | Out-Null
    [IO.Directory]::CreateDirectory($sourceRoot) | Out-Null
    $env:LOCALAPPDATA = Join-Path $fixture 'local'
    $names = @('paseo','paseo-advisor','paseo-committee','paseo-handoff','paseo-help','paseo-plugin')
    foreach ($name in $names) {
        $source = Join-Path $sourceRoot $name
        [IO.Directory]::CreateDirectory($source) | Out-Null
        [IO.File]::WriteAllText((Join-Path $source 'keep.txt'),'source data')
        New-Item -ItemType Junction -Path (Join-Path $skills $name) -Target $source | Out-Null
    }
    [IO.Directory]::Delete((Join-Path $sourceRoot 'paseo-handoff'), $true)
    $symbolicTarget = Join-Path $skills 'paseo'
    $symbolicSource = Join-Path $sourceRoot 'paseo'
    [IO.Directory]::Delete($symbolicTarget)
    try {
        New-Item -ItemType SymbolicLink -Path $symbolicTarget -Target $symbolicSource -ErrorAction Stop | Out-Null
        $hasDirectorySymlink = $true
    } catch {
        Write-Host 'SKIP: directory symbolic-link fixture unavailable; junction fixtures still cover owned-link cleanup.'
        if (Get-Item -LiteralPath $symbolicTarget -Force -ErrorAction SilentlyContinue) {
            [IO.Directory]::Delete($symbolicTarget)
        }
        New-Item -ItemType Junction -Path $symbolicTarget -Target $symbolicSource | Out-Null
        $hasDirectorySymlink = $false
    }
    $foreignSource = Join-Path $foreignRoot 'paseo-advisor'
    [IO.Directory]::CreateDirectory($foreignSource) | Out-Null
    [IO.File]::WriteAllText((Join-Path $foreignSource 'keep.txt'),'foreign data')
    [IO.Directory]::Delete((Join-Path $skills 'paseo-advisor'))
    New-Item -ItemType Junction -Path (Join-Path $skills 'paseo-advisor') -Target $foreignSource | Out-Null

    $realDirectory = Join-Path $skills 'paseo-plugin'
    [IO.Directory]::Delete($realDirectory)
    [IO.Directory]::CreateDirectory($realDirectory) | Out-Null
    [IO.File]::WriteAllText((Join-Path $realDirectory 'keep.txt'),'real directory')
    $fileLinkTarget = Join-Path $sourceRoot 'paseo-help'
    [IO.Directory]::Delete($fileLinkTarget, $true)
    [IO.File]::WriteAllText($fileLinkTarget,'file-link target')
    $fileLink = Join-Path $skills 'paseo-help'
    [IO.Directory]::Delete($fileLink)
    try {
        New-Item -ItemType SymbolicLink -Path $fileLink -Target $fileLinkTarget -ErrorAction Stop | Out-Null
        $hasFileSymlink = $true
    } catch {
        Write-Host 'SKIP: file symbolic-link fixture unavailable; plain file preservation is covered.'
        if (Get-Item -LiteralPath $fileLink -Force -ErrorAction SilentlyContinue) {
            $partial = Get-Item -LiteralPath $fileLink -Force
            if ($partial.Attributes -band [IO.FileAttributes]::Directory) { [IO.Directory]::Delete($fileLink) }
            else { [IO.File]::Delete($fileLink) }
        }
        [IO.File]::WriteAllText($fileLink,'real file')
        $hasFileSymlink = $false
    }

    $legacyLocal = Join-Path $env:LOCALAPPDATA 'Programs\Paseo\resources\bin'
    $userPath = "C:\Keep Me;$legacyLocal/;C:\Tail"
    $preview = Invoke-PaseoRetirement -HomeRoot $fixtureHome -DotfilesRoot $repo -UserPath $userPath
    Assert-That ($preview.PathChanged) 'preview detects the legacy PATH entry'
    Assert-That ($preview.UserPath -ceq 'C:\Keep Me;C:\Tail') 'preview calculates the filtered PATH'
    foreach ($name in @('paseo','paseo-committee','paseo-handoff','paseo-plugin')) {
        Assert-That ($null -ne (Get-Item -LiteralPath (Join-Path $skills $name) -Force -ErrorAction SilentlyContinue)) "preview preserves $name"
    }
    Assert-That ($null -ne (Get-Item -LiteralPath $fileLink -Force -ErrorAction SilentlyContinue)) 'preview preserves file entry'
    if ($hasDirectorySymlink) {
        Assert-That ((Get-Item -LiteralPath $symbolicTarget -Force).LinkType -eq 'SymbolicLink') 'symbolic-link fixture created'
    }

    $applied = Invoke-PaseoRetirement -HomeRoot $fixtureHome -DotfilesRoot $repo -UserPath $userPath -Apply
    Assert-That ($applied.PathChanged) 'apply reports PATH change'
    Assert-That ($applied.UserPath -ceq 'C:\Keep Me;C:\Tail') 'apply returns only unrelated PATH entries'
    foreach ($name in @('paseo','paseo-committee','paseo-handoff')) {
        Assert-That (-not (Get-Item -LiteralPath (Join-Path $skills $name) -Force -ErrorAction SilentlyContinue)) "owned directory link removed: $name"
    }
    foreach ($name in @('paseo','paseo-committee')) {
        Assert-That (Test-Path -LiteralPath (Join-Path $sourceRoot "$name\keep.txt")) "source data preserved: $name"
    }
    Assert-That (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'paseo-handoff'))) 'dangling link source remains absent'
    Assert-That ((Get-Item -LiteralPath (Join-Path $skills 'paseo-advisor') -Force).LinkTarget -ieq $foreignSource) 'foreign junction preserved'
    Assert-That (Test-Path -LiteralPath (Join-Path $sourceRoot 'paseo\keep.txt')) 'directory link source data preserved'
    Assert-That ([IO.File]::ReadAllText((Join-Path $realDirectory 'keep.txt')) -ceq 'real directory') 'real directory preserved'
    if ($hasFileSymlink) {
        $fileLinkItem = Get-Item -LiteralPath $fileLink -Force
        Assert-That ($fileLinkItem.LinkType -eq 'SymbolicLink') 'file symbolic link preserved'
        Assert-That (-not ($fileLinkItem.Attributes -band [IO.FileAttributes]::Directory)) 'file link is not a directory link'
        Assert-That ([IO.File]::ReadAllText($fileLink) -ceq 'file-link target') 'file-link target preserved'
    } else {
        Assert-That ([IO.File]::ReadAllText($fileLink) -ceq 'real file') 'real file preserved'
    }
    $again = Invoke-PaseoRetirement -HomeRoot $fixtureHome -DotfilesRoot $repo -UserPath $applied.UserPath -Apply
    Assert-That (-not $again.PathChanged) 'second application is PATH-idempotent'

    # A separate temporary home keeps this refusal fixture independent from the
    # real directory and file entries preserved in the migration fixture.
    [IO.Directory]::Delete((Join-Path $skills 'paseo-advisor'))
    $outside = Join-Path $fixture 'outside-skills'
    [IO.Directory]::CreateDirectory($outside) | Out-Null
    [IO.File]::WriteAllText((Join-Path $outside 'paseo'),'foreign')
    [IO.Directory]::CreateDirectory((Split-Path $guardSkills -Parent)) | Out-Null
    New-Item -ItemType Junction -Path $guardSkills -Target $outside | Out-Null
    Assert-Throws { Invoke-PaseoRetirement -HomeRoot $guardHome -DotfilesRoot $repo -UserPath $userPath -Apply } 'skills parent reparse guard'
    Assert-That ([IO.File]::ReadAllText((Join-Path $outside 'paseo')) -ceq 'foreign') 'parent guard leaves foreign tree untouched'
    [IO.Directory]::Delete($guardSkills)
} finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    if (Test-Path -LiteralPath $guardSkills) {
        $guardItem = Get-Item -LiteralPath $guardSkills -Force -ErrorAction SilentlyContinue
        if ($guardItem.LinkType -in @('Junction','SymbolicLink')) { [IO.Directory]::Delete($guardSkills) }
    }
    if (Test-Path -LiteralPath $skills) {
        $skillsItem = Get-Item -LiteralPath $skills -Force -ErrorAction SilentlyContinue
        if ($skillsItem.LinkType -in @('Junction','SymbolicLink')) {
            [IO.Directory]::Delete($skills)
        } elseif ($skillsItem.PSIsContainer) {
            foreach ($child in Get-ChildItem -LiteralPath $skills -Force) {
                if ($child.LinkType -in @('Junction','SymbolicLink')) {
                    if ($child.Attributes -band [IO.FileAttributes]::Directory) { [IO.Directory]::Delete($child.FullName) }
                    else { [IO.File]::Delete($child.FullName) }
                }
            }
        }
    }
    if (Test-Path -LiteralPath $fixture) { [IO.Directory]::Delete($fixture, $true) }
}

Write-Host 'PASS: Windows Paseo retirement fixtures'
