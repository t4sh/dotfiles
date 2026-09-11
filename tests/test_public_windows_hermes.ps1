#Requires -Version 7.4
# Public-owned fixtures. Shortcuts and fake updater state stay under Windows Temp.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
. (Join-Path $root 'scripts/lib/windows-common.ps1')
Assert-DotfilesWindows
$pwsh = Resolve-DotfilesPwsh
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('public-hermes-' + [guid]::NewGuid().ToString('N'))
$global:PublicHermesFixtureState = @{}
$oldHome = $env:HERMES_HOME
$oldRoot = $env:HERMES_DESKTOP_HERMES_ROOT
try {
    $runtimeHome = Join-Path $fixture 'profile with spaces'
    $runtime = Join-Path $runtimeHome 'hermes-agent'
    $programs = Join-Path $fixture 'Programs'
    [IO.Directory]::CreateDirectory((Join-Path $runtime 'venv/Scripts')) | Out-Null
    [IO.Directory]::CreateDirectory($programs) | Out-Null
    [IO.File]::WriteAllText((Join-Path $runtime 'venv/Scripts/python.exe'), 'fixture; never executed')
    $shortcutPath = Join-Path $programs 'Hermes.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $pwsh
    $shortcut.Arguments = '-NoProfile -Command exit'
    $shortcut.Save()
    $originalHash = (Get-FileHash -LiteralPath $shortcutPath).Hash
    $launcher = Join-Path $root 'scripts/setup-windows-hermes-launcher.ps1'
    $options = @{ HermesHome=$runtimeHome; HermesRoot=$runtime; ProgramsDirectory=$programs }
    & $launcher @options | Out-Null
    if ((Get-FileHash $shortcutPath).Hash -ne $originalHash) { throw 'Preview changed shortcut' }
    $failed = $false
    try { & $launcher -Check @options | Out-Null } catch { $failed = $_.Exception.Message -match 'launcher differs' }
    if (-not $failed) { throw 'Drift check accepted packaged shortcut' }
    & $launcher -Apply @options | Out-Null
    & $launcher -Check @options | Out-Null
    $configured = (Get-FileHash $shortcutPath).Hash
    & $launcher -Apply @options | Out-Null
    if ((Get-FileHash $shortcutPath).Hash -ne $configured) { throw 'Repeated setup rewrote shortcut' }
    if ((Get-FileHash ($shortcutPath+'.before-dotfiles')).Hash -ne $originalHash) { throw 'Original shortcut backup differs' }
    $shortcut = $shell.CreateShortcut($shortcutPath)
    if ($shortcut.TargetPath -ine $pwsh -or $shortcut.Arguments -notlike '*start-windows-hermes.ps1*' -or $shortcut.Arguments -notlike ('*-HermesHome "'+$runtimeHome+'"*')) { throw 'Shortcut target or quoted home is incorrect' }

    # Execute real wrappers with fake native commands and fake follow-up stages.
    $scripts = Join-Path $fixture 'scripts'
    [IO.Directory]::CreateDirectory((Join-Path $scripts 'lib')) | Out-Null
    foreach ($name in @('start-windows-hermes.ps1','update-windows-hermes.ps1')) {
        Copy-Item -LiteralPath (Join-Path $root "scripts/$name") -Destination (Join-Path $scripts $name)
    }
    $common = @'
function Assert-DotfilesWindows {}
function Assert-DotfilesPreferenceFile([string]$Path) { if (-not (Test-Path -LiteralPath $Path)) { throw 'Fixture runtime missing' } }
function Invoke-DotfilesNativeUtf8([string]$File,[string[]]$Arguments) {
    $global:PublicHermesFixtureState.nativeCalls++
    $global:PublicHermesFixtureState.observedArguments = $Arguments
    if ($global:PublicHermesFixtureState.failNative) { throw 'fixture native failure (exit 2)' }
    Write-Output 'fixture native success'
}
'@
    [IO.File]::WriteAllText((Join-Path $scripts 'lib/windows-common.ps1'), $common)
    [IO.File]::WriteAllText((Join-Path $scripts 'setup-windows-hermes-launcher.ps1'), 'param([switch]$Apply,[string]$HermesHome,[string]$HermesRoot); $global:PublicHermesFixtureState.repairCalls++')
    [IO.File]::WriteAllText((Join-Path $scripts 'setup-windows-hermes.ps1'), 'param([switch]$Check,[string]$HermesHome); $global:PublicHermesFixtureState.checkCalls++')
    [IO.Directory]::CreateDirectory((Join-Path $runtime 'hermes_cli')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $runtime 'hermes_cli/main.py'), '# fixture')
    $global:PublicHermesFixtureState.nativeCalls=0; $global:PublicHermesFixtureState.repairCalls=0; $global:PublicHermesFixtureState.checkCalls=0; $global:PublicHermesFixtureState.failNative=$false
    & (Join-Path $scripts 'start-windows-hermes.ps1') -HermesHome $runtimeHome -HermesRoot $runtime | Out-Null
    if (($global:PublicHermesFixtureState.observedArguments -join ' ') -cne '-u -m hermes_cli.main desktop --source --skip-build') { throw 'Source launch invoked a build or incorrect command' }
    if ($env:HERMES_HOME -cne $runtimeHome -or $env:HERMES_DESKTOP_HERMES_ROOT -cne $runtime) { throw 'Source launch selected wrong runtime' }
    $global:PublicHermesFixtureState.nativeCalls=0
    $updater = Join-Path $scripts 'update-windows-hermes.ps1'
    & $updater -DryRun | Out-Null
    if ($global:PublicHermesFixtureState.nativeCalls -or $global:PublicHermesFixtureState.repairCalls -or $global:PublicHermesFixtureState.checkCalls) { throw 'Dry run performed work' }
    & $updater | Out-Null
    if ($global:PublicHermesFixtureState.nativeCalls -ne 1 -or $global:PublicHermesFixtureState.repairCalls -ne 1 -or $global:PublicHermesFixtureState.checkCalls -ne 1) { throw 'Update did not run once and verify both follow-ups' }
    if (($global:PublicHermesFixtureState.observedArguments -join ' ') -cne '-u -m hermes_cli.main update --yes') { throw 'Native update arguments changed' }
    $global:PublicHermesFixtureState.failNative=$true
    $failed=$false
    try { & $updater | Out-Null } catch { $failed=$_.Exception.Message -match 'exit 2.*Log:' }
    if (-not $failed -or $global:PublicHermesFixtureState.repairCalls -ne 1 -or $global:PublicHermesFixtureState.checkCalls -ne 1) { throw 'Failed update hid status or ran success stages' }
    $env:HERMES_HOME=Join-Path $fixture 'absent'
    & $updater | Out-Null
    if ($global:PublicHermesFixtureState.nativeCalls -ne 2) { throw 'Absent installation attempted an update' }
} finally {
    Remove-Variable PublicHermesFixtureState -Scope Global
    $env:HERMES_HOME=$oldHome
    $env:HERMES_DESKTOP_HERMES_ROOT=$oldRoot
    $resolved=[IO.Path]::GetFullPath($fixture)
    if ((Split-Path $resolved -Parent) -ine [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') -or (Split-Path $resolved -Leaf) -notmatch '^public-hermes-[0-9a-f]{32}$') { throw 'Unsafe fixture cleanup path' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
Write-Output 'PASS: public Hermes shortcut preview/drift/repair/backup/idempotence, source arguments, update success/failure/dry-run and absent installation.'
