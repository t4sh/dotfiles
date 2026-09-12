# Discovery must not report an existing but unusable interpreter as ready.
#Requires -Version 7.4
param([string]$Repository = (Split-Path $PSScriptRoot))
$ErrorActionPreference='Stop'
. (Join-Path $Repository 'scripts/lib/windows-common.ps1')
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('python-discovery-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture)|Out-Null
try {
    $fakePython=Join-Path $fixture 'python.exe'
    $fakeUv=Join-Path $fixture 'uv.cmd'
    Write-DotfilesText $fakePython 'not an executable; existing-path regression fixture'
    Write-DotfilesText $fakeUv ("@echo off`r`necho "+$fakePython+"`r`nexit /b 0`r`n")
    function Get-Command {param($Name,$ErrorAction); if($Name -eq 'uv.exe'){[pscustomobject]@{Source=$fakeUv}}else{throw 'Unexpected command discovery'}}
    $failure=''
    try {Resolve-DotfilesPython|Out-Null} catch {$failure=$_.Exception.Message}
    if($failure -notlike '*Managed Python cannot run*' -or $failure -notlike "*$fakePython*") {throw 'Discovery accepted unusable Python or lost its diagnostic path'}
    # Exercise Hermes's real updater entry point, not only global uv discovery.
    $previousHome=$env:HERMES_HOME
    try {
        $env:HERMES_HOME=Join-Path $fixture 'hermes'
        $hermesPython=Join-Path $env:HERMES_HOME 'hermes-agent/venv/Scripts/python.exe'
        Write-DotfilesText $hermesPython 'not an executable; Hermes startup regression fixture'
        $output=[Collections.Generic.List[string]]::new()
        $failure=''
        try { & (Join-Path $Repository 'scripts/update-windows-hermes.ps1') | ForEach-Object { $output.Add([string]$_) } } catch {$failure=$_.Exception.Message}
        $log=($output | Where-Object {$_ -like 'Hermes update log: *'}) -replace '^Hermes update log: ',''
        if($failure -notlike '*Hermes Python cannot run*' -or !$failure.Contains($hermesPython)) {throw 'Hermes omitted its runtime readiness diagnostic'}
        if(!$log -or !(Test-Path -LiteralPath $log) -or !(Get-Content $log -Raw).Contains($failure)) {throw 'Hermes startup failure was not retained in its reported log'}
    } finally {$env:HERMES_HOME=$previousHome}
    Write-Output 'PASS: unusable Python is rejected during discovery with its actual path.'
} finally {
    Remove-Item Function:\Get-Command -ErrorAction SilentlyContinue
    $resolved=[IO.Path]::GetFullPath($fixture)
    if((Split-Path $resolved -Parent) -ine [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')){throw 'Unsafe fixture cleanup path'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
