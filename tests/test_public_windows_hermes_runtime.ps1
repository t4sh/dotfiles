#Requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('public-hermes-runtime-' + [guid]::NewGuid().ToString('N'))
$previousHome = $env:HERMES_HOME
$previousRoot = $env:HERMES_DESKTOP_HERMES_ROOT
$previousLocal = $env:LOCALAPPDATA
try {
    New-Item -ItemType Directory -Force (Join-Path $fixture 'lib') | Out-Null
    $start = Join-Path $fixture 'start-windows-hermes.ps1'
    Copy-Item (Join-Path $root 'scripts/start-windows-hermes.ps1') $start
    Copy-Item (Join-Path $root 'scripts/lib/windows-hermes.ps1') (Join-Path $fixture 'lib/windows-hermes.ps1')
    # Run the actual entry point on the real library, replacing only OS guards
    # and native execution: shared path resolution stays under test.
    ((Get-Content -LiteralPath (Join-Path $root 'scripts/lib/windows-common.ps1') -Raw).TrimEnd() + "`n" + @'
function Assert-DotfilesWindows {}
function Assert-DotfilesPreferenceFile($Path) { $global:HermesStartChecked += $Path }
function Invoke-DotfilesNativeUtf8($File, $Arguments) {
    $global:HermesStartCall = @{
        File = $File; Arguments = $Arguments
        Home = $env:HERMES_HOME; Root = $env:HERMES_DESKTOP_HERMES_ROOT
    }
}
'@) | Set-Content (Join-Path $fixture 'lib/windows-common.ps1')
    function Assert-Launch($ExpectedHome, $ExpectedRoot, $ExpectedPython) {
        $call = $global:HermesStartCall
        if ($call.Home -cne $ExpectedHome -or $call.Root -cne $ExpectedRoot -or $call.File -cne $ExpectedPython) {
            throw 'Source launch selected the wrong profile, checkout or Python'
        }
        if (($call.Arguments -join '|') -cne '-u|-m|hermes_cli.main|desktop|--source|--skip-build') {
            throw 'Source launch changed its no-build invocation'
        }
        if (($global:HermesStartChecked -join '|') -cne ((Join-Path $ExpectedRoot 'hermes_cli/main.py') + '|' + $ExpectedPython)) {
            throw 'Source launch skipped runtime or checkout validation'
        }
    }
    $env:LOCALAPPDATA = Join-Path $fixture 'local data'
    $env:HERMES_HOME = $null
    $global:HermesStartChecked = @()
    $defaultHome = Join-Path $env:LOCALAPPDATA 'hermes'
    $defaultRoot = Join-Path $defaultHome 'hermes-agent'
    New-Item -ItemType Directory -Force (Join-Path $defaultRoot 'venv/Scripts') | Out-Null
    Set-Content (Join-Path $defaultRoot 'venv/Scripts/python.exe') 'fixture'
    & $start
    Assert-Launch $defaultHome $defaultRoot (Join-Path $defaultRoot 'venv/Scripts/python.exe')

    $env:HERMES_HOME = Join-Path $fixture 'environment profile'
    $environmentHome = $env:HERMES_HOME
    $environmentRoot = Join-Path $environmentHome 'hermes-agent'
    New-Item -ItemType Directory -Force (Join-Path $environmentRoot 'venv/Scripts') | Out-Null
    Set-Content (Join-Path $environmentRoot 'venv/Scripts/python.exe') 'fixture'
    $global:HermesStartChecked = @()
    & $start
    Assert-Launch $environmentHome $environmentRoot (Join-Path $environmentRoot 'venv/Scripts/python.exe')

    $explicitHome = Join-Path $fixture 'explicit profile'
    $explicitRoot = Join-Path $fixture 'explicit checkout'
    $explicitPython = Join-Path $fixture 'alternate python.exe'
    $global:HermesStartChecked = @()
    & $start -HermesHome $explicitHome -HermesRoot $explicitRoot -Python $explicitPython
    Assert-Launch $explicitHome $explicitRoot $explicitPython
    # Modern installs ask their published launcher for the selected interpreter.
    # Never fall back to a stale venv when PM owns this checkout.
    $managedRoot = Join-Path $fixture 'managed checkout'
    New-Item -ItemType Directory -Force (Join-Path $managedRoot 'pm'),(Join-Path $managedRoot '.hermes/bin') | Out-Null
    $published = Join-Path $managedRoot '.hermes/bin/hermes.cmd'
    Set-Content $published 'fixture launcher'
    Set-Content $explicitPython 'fixture interpreter'
    . (Join-Path $fixture 'lib/windows-common.ps1')
    . (Join-Path $fixture 'lib/windows-hermes.ps1')
    function Invoke-DotfilesNativeUtf8($File, $Arguments) {
        if ($File -eq $published) {
            if (($Arguments -join '|') -cne '--print-runtime-command') { throw 'Unexpected launcher query' }
            return (ConvertTo-Json -Compress -InputObject @($explicitPython,'-I','-c','upstream bootstrap'))
        }
        if ($File -ne $explicitPython -or $env:HERMES_HOME -ne $explicitHome) { throw 'Managed runtime/profile selection failed' }
        if (($Arguments[0..2] -join '|') -cne ('-I|' + (Join-Path $fixture 'hermes-python.py') + '|' + $managedRoot)) { throw 'Managed bootstrap arguments changed' }
        if (($Arguments[3..5] -join '|') -cne '-c|print("quoted text")|space argument') { throw 'Python arguments changed' }
        if ($failManaged) { throw 'fixture runtime failure' }
    }
    $env:HERMES_HOME = 'previous profile'
    $failManaged = $false
    Invoke-DotfilesHermesPython -HermesHome $explicitHome -HermesRoot $managedRoot -Arguments @('-c','print("quoted text")','space argument')
    if ($env:HERMES_HOME -cne 'previous profile') { throw 'Managed invocation leaked profile environment' }
    $failManaged = $true
    try { Invoke-DotfilesHermesPython -HermesHome $explicitHome -HermesRoot $managedRoot -Arguments @('-c','print("quoted text")','space argument'); throw 'Expected failure' }
    catch { if ($_.Exception.Message -ne 'fixture runtime failure') { throw } }
    if ($env:HERMES_HOME -cne 'previous profile') { throw 'Failed invocation leaked profile environment' }
    Write-Output 'PASS: Hermes source launch defaults, environment, explicit overrides, guards and no-build flags.'
} finally {
    $env:HERMES_HOME = $previousHome
    $env:HERMES_DESKTOP_HERMES_ROOT = $previousRoot
    $env:LOCALAPPDATA = $previousLocal
    Remove-Variable HermesStartCall,HermesStartChecked -Scope Global -ErrorAction SilentlyContinue
    $resolved = [IO.Path]::GetFullPath($fixture)
    if ((Split-Path $resolved -Parent) -ine [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') -or (Split-Path $resolved -Leaf) -notmatch '^public-hermes-runtime-[0-9a-f]{32}$') { throw 'Unsafe fixture cleanup path' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
