#Requires -Version 7.0
[CmdletBinding()]
param([switch]$Apply, [string]$CacheDirectory = (Join-Path $env:TEMP 'dotfiles-fonts'), [string[]]$Only)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\windows-common.ps1')
Assert-DotfilesWindows
$tokens = @(Get-Content (Join-Path (Split-Path $PSScriptRoot) 'Brewfile') | ForEach-Object { if ($_ -match '^cask "(font-[^"]+)"') { $matches[1] } })
if (-not $Apply) { $tokens; return }
if ($Only) {
    if (@($Only | Where-Object { $_ -notin $tokens }).Count) { throw 'Unknown Brewfile font selection.' }
    $tokens = @($tokens | Where-Object { $_ -in $Only })
}
$fontDirectory = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$registryPath = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
New-Item -ItemType Directory -Path $fontDirectory,$CacheDirectory -Force | Out-Null
if (-not (Test-Path $registryPath)) { New-Item -Path $registryPath -Force | Out-Null }
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class DotfilesFonts { [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] public static extern int AddFontResourceW(string path); }'
$results = foreach ($token in $tokens) {
    try {
        $metadata = Invoke-RestMethod -Uri "https://formulae.brew.sh/api/cask/$token.json" -TimeoutSec 30
        $declared = @($metadata.artifacts | ForEach-Object { if ($_.font) { $_.font[0] } })
        if ($declared.Count -eq 0) { throw 'No declared font artifacts' }
        # The substitute CTAN archive has no independently verified pinned digest.
        # Preserve existing fonts; an explicit manual disposition is safer than no_check.
        if ($token -eq 'font-computer-modern') {
            Write-Warning 'Computer Modern is manual: verify a CTAN release before installation. Existing fonts preserved.'
            [pscustomobject]@{Font=$token;Count=0;Status='Manual';Detail='CTAN substitute requires a reviewed checksum'}
            continue
        }
        if ($metadata.sha256 -notmatch '^[0-9a-f]{64}$') { throw 'No verifiable font checksum; refusing automatic installation' }
        $directory = Join-Path (Join-Path $CacheDirectory $token) $metadata.sha256
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $download = Join-Path $directory ([uri]::UnescapeDataString([IO.Path]::GetFileName(([uri]$metadata.url).AbsolutePath)))
        if (-not (Test-Path -LiteralPath $download)) { Invoke-WebRequest -Uri $metadata.url -OutFile $download -TimeoutSec 90 }
        if ($metadata.sha256 -match '^[0-9a-f]{64}$' -and (Get-FileHash -LiteralPath $download).Hash -ne $metadata.sha256) { throw 'Font download hash mismatch' }
        $extension = [IO.Path]::GetExtension($download)
        if ($extension -notin @('.ttf','.otf','.ttc')) {
            $members=@(& tar.exe -tf $download)
            if ($LASTEXITCODE -ne 0 -or -not $members.Count) { throw 'Cannot inspect font archive' }
            if (@($members | Where-Object { $_ -match '(^|[\\/])\.\.([\\/]|$)|^[\\/]|^[a-zA-Z]:' }).Count) { throw 'Unsafe font archive path' }
            $details=@(& tar.exe -tvf $download)
            if ($LASTEXITCODE -ne 0 -or @($details | Where-Object { $_ -notmatch '^[-d]' }).Count) { throw 'Font archive contains links or unsupported file types' }
            & tar.exe -xf $download -C $directory
            if ($LASTEXITCODE -ne 0) { throw 'Font archive extraction failed' }
        }
        $count = 0
        foreach ($artifact in $declared) {
            $basename = [IO.Path]::GetFileName($artifact)
            if ([IO.Path]::GetExtension($basename) -notin @('.ttf','.otf','.ttc')) { continue }
            $source = @(Get-ChildItem -LiteralPath $directory -Recurse -File | Where-Object Name -EQ $basename) | Select-Object -First 1
            if (-not $source) { throw "Declared font not found: $artifact" }
            $target = Join-Path $fontDirectory $basename
            if (-not (Test-Path -LiteralPath $target)) { Copy-Item -LiteralPath $source.FullName -Destination $target }
            elseif ((Get-FileHash -LiteralPath $target).Hash -ne (Get-FileHash -LiteralPath $source.FullName).Hash) { throw "Existing font differs; preserved: $target" }
            New-ItemProperty -Path $registryPath -Name ([IO.Path]::GetFileNameWithoutExtension($basename) + ' (TrueType)') -Value $target -PropertyType String -Force | Out-Null
            if ([DotfilesFonts]::AddFontResourceW($target) -eq 0) { throw "Windows could not load font: $target" }
            $count++
        }
        Write-Host "$token : $count fonts"
        [pscustomobject]@{Font=$token;Count=$count;Status='Installed';Detail=''}
    } catch {
        Write-Host "$token : $($_.Exception.Message)"
        [pscustomobject]@{Font=$token;Count=0;Status='Needs attention';Detail=$_.Exception.Message}
    }
}
$results | Export-Csv -LiteralPath (Join-Path $CacheDirectory 'results.csv') -NoTypeInformation
if (@($results | Where-Object Status -EQ 'Needs attention').Count) { throw 'Font installation incomplete; review results.csv.' }
