# Exercise the real CMD wrapper without network access or live skill changes.
#Requires -Version 7.4
param([string]$Repository = (Split-Path $PSScriptRoot), [string]$Python)
$ErrorActionPreference = 'Stop'
. (Join-Path $Repository 'scripts/lib/windows-common.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('skills-prompt-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
$previousNpx = $env:NPX_REAL
$previousPython = $env:PYTHON_BIN
try {
    $env:NPX_REAL = Join-Path $fixture 'fake npx.cmd'
    $env:PYTHON_BIN = if ($Python) { $Python } else { Resolve-DotfilesPython }
    Write-DotfilesText $env:NPX_REAL @'
@echo off
if not "%~1"=="--yes" (
  echo npm install confirmation would block here
  exit /b 41
)
if not "%~2"=="skills" exit /b 42
if not "%~3"=="add" exit /b 43
if not "%~4"=="fixture/source" exit /b 44
if not "%~6"=="two words" exit /b 45
set "answer="
set /p "answer="
if defined answer exit /b 46
exit /b 0
'@
    $output = @('unexpected terminal input' | & (Join-Path $Repository 'scripts/npx-skills-windows.cmd') skills add fixture/source --skill 'two words' -g -y)
    if ($LASTEXITCODE -ne 0) { throw "npm confirmation regression: wrapper exited $LASTEXITCODE" }
    if (($output -join '|') -notmatch 'Checking skills from source: fixture/source') { throw 'Source progress lost' }
    Write-Output 'PASS: npm consent precedes the command; arguments survive; child stdin is closed.'
    Write-DotfilesText $env:NPX_REAL "@echo off`r`necho installer failure fixture`r`nexit /b 17`r`n"
    $output = @(& (Join-Path $Repository 'scripts/npx-skills-windows.cmd') skills add fixture/source --skill alpha -g -y)
    if ($LASTEXITCODE -ne 17 -or ($output -join '|') -notmatch 'exit 17.*log:') { throw 'Installer failure status/log lost' }
    Write-Output 'PASS: installer failures retain exit status and diagnostic log location.'
} finally {
    $env:NPX_REAL = $previousNpx
    $env:PYTHON_BIN = $previousPython
    # Only remove this test-owned directory, contained in the Windows temp root.
    if (([IO.Path]::GetFullPath($fixture)).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $fixture -Recurse -Force
    }
}
