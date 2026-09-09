#Requires -Version 7.0
[CmdletBinding()]
param([ValidateSet('code','cursor')][string]$Editor='code',[switch]$Apply,[switch]$Check)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'lib\windows-common.ps1')
Assert-DotfilesWindows
$root=Split-Path $PSScriptRoot
$wanted=@(Get-Content -LiteralPath (Join-Path $root 'Brewfile') | ForEach-Object {if($_ -match '^vscode "([^"]+)"'){$matches[1]}})
$exceptions=@(Import-Csv -LiteralPath (Join-Path $root 'config\windows-extensions.tsv') -Delimiter "`t" | Where-Object Editor -EQ $Editor)
foreach($exception in $exceptions){if($exception.Id -notin $wanted){throw "Stale extension exception: $($exception.Id)"}}
$wanted=@($wanted | Where-Object {$_ -notin $exceptions.Id})
$command=Get-Command $Editor -ErrorAction Stop
$installed=@(& $command.Source --list-extensions 2>$null)
if($LASTEXITCODE -ne 0){throw "Cannot inventory $Editor extensions"}
$missing=@($wanted | Where-Object {$_ -notin $installed})
$exceptions | ForEach-Object {Write-Output "Excluded $($_.Id): $($_.Reason)"}
if($Check){if($missing.Count){throw "$Editor missing extensions: $($missing -join ', ')"}; Write-Output "$Editor : $($wanted.Count) applicable Brewfile extensions installed."; return}
if(-not $Apply){$missing;return}
$failed=@()
foreach($id in $missing){try{Invoke-DotfilesNative $command.Source @('--install-extension',$id)}catch{$failed+=$id;Write-Warning $_.Exception.Message}}
$verified=@(& $command.Source --list-extensions 2>$null)
if($LASTEXITCODE -ne 0){throw 'Post-install extension inventory failed.'}
$failed+=@($wanted | Where-Object {$_ -notin $verified})
if($failed.Count){throw "Extensions incomplete: $(($failed | Select-Object -Unique) -join ', '). No restricted binaries were copied."}
