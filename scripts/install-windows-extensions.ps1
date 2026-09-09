#Requires -Version 7.0
[CmdletBinding()]
param([ValidateSet('code','cursor')][string]$Editor='code',[switch]$Apply,[switch]$Check,
    [string]$UserDataDir, [string]$ExtensionsDir, [string]$Profile)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'lib\windows-common.ps1')
Assert-DotfilesWindows
if ([bool]$UserDataDir -ne [bool]$ExtensionsDir) { throw 'Isolation requires both -UserDataDir and -ExtensionsDir; no extension operation started.' }
$scope=@()
if ($UserDataDir) { $scope+=@('--user-data-dir',[IO.Path]::GetFullPath($UserDataDir),'--extensions-dir',[IO.Path]::GetFullPath($ExtensionsDir)) }
if ($Profile) { $scope+=@('--profile',$Profile) }
$root=Split-Path $PSScriptRoot
$wanted=@(Get-Content -LiteralPath (Join-Path $root 'Brewfile') | ForEach-Object {if($_ -match '^vscode "([^"]+)"'){$matches[1]}})
$exceptions=@(Import-Csv -LiteralPath (Join-Path $root 'config\windows-extensions.tsv') -Delimiter "`t" | Where-Object Editor -EQ $Editor)
foreach($exception in $exceptions){if($exception.Id -notin $wanted){throw "Stale extension exception: $($exception.Id)"}}
$wanted=@($wanted | Where-Object {$_ -notin $exceptions.Id})
$wanted=@($wanted + @($exceptions | Where-Object Replacement | Select-Object -ExpandProperty Replacement) | Sort-Object -Unique)
function Test-ExtensionInstalled([string]$Target, [string[]]$Inventory) {
    if ($Target.Contains('@')) { return $Target -in $Inventory }
    return $Target -in @($Inventory | ForEach-Object { ($_ -split '@')[0] })
}
$command=Get-Command $Editor -ErrorAction Stop
$installed=@(& $command.Source @scope --list-extensions --show-versions 2>$null)
if($LASTEXITCODE -ne 0){throw "Cannot inventory $Editor extensions"}
$missing=@($wanted | Where-Object {-not (Test-ExtensionInstalled $_ $installed)})
$exceptions | ForEach-Object {
    if ($_.Replacement) { Write-Output "Replacement $($_.Id) -> $($_.Replacement): $($_.Reason)" }
    else { Write-Output "Excluded $($_.Id): $($_.Reason)" }
}
if($Check){if($missing.Count){throw "$Editor missing extensions: $($missing -join ', ')"}; Write-Output "$Editor : $($wanted.Count) declared extensions installed (Brewfile plus Windows replacements). Activation is a separate check."; return}
if(-not $Apply){$missing;return}
$failed=@()
foreach($id in $missing){
    try {
        $source=@($exceptions | Where-Object { $_.Replacement -eq $id -and $_.DownloadUrl })
        $target=$id
        if ($source.Count) {
            if ($source.Count -ne 1 -or $source[0].Sha256 -notmatch '^[a-fA-F0-9]{64}$' -or ([uri]$source[0].DownloadUrl).Scheme -ne 'https') { throw "Invalid pinned release declaration: $id" }
            $cache=Join-Path ([IO.Path]::GetTempPath()) 'dotfiles-editor-releases'
            [IO.Directory]::CreateDirectory($cache) | Out-Null
            $target=Join-Path $cache ($source[0].Sha256.ToLowerInvariant()+'.vsix')
            if (-not (Test-Path -LiteralPath $target)) { Invoke-WebRequest -Uri $source[0].DownloadUrl -OutFile $target }
            if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $source[0].Sha256) { throw "Release checksum mismatch: $id. Cached file retained at $target; no extension installed." }
        }
        # A reviewed version pin may need to replace an already installed broken release.
        $installArgs=$scope+@('--install-extension',$target)
        if ($id.Contains('@')) { $installArgs+='--force' }
        Invoke-DotfilesNative $command.Source $installArgs
    } catch {$failed+=$id;Write-Warning $_.Exception.Message}
}
$verified=@(& $command.Source @scope --list-extensions --show-versions 2>$null)
if($LASTEXITCODE -ne 0){throw 'Post-install extension inventory failed.'}
$failed+=@($wanted | Where-Object {-not (Test-ExtensionInstalled $_ $verified)})
if($failed.Count){throw "Extensions incomplete: $(($failed | Select-Object -Unique) -join ', '). No restricted binaries were copied."}
