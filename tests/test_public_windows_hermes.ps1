#Requires -Version 7.4
# Public-owned fixtures. Shortcuts and fake updater state stay under Windows Temp.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
# This public-owned wrapper must work without private integration files.
if ((Get-Content (Join-Path $root 'scripts/update-windows-hermes.ps1') -Raw).Contains('install-hermes-rulebook.py')) {
    throw 'Public Hermes updater depends on the private rulebook installer'
}
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
    $taskbar = Join-Path $fixture 'TaskBar'
    [IO.Directory]::CreateDirectory($taskbar) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $runtime 'venv/Scripts')) | Out-Null
    [IO.Directory]::CreateDirectory($programs) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $runtime 'apps/desktop/assets')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $runtime 'apps/desktop/assets/icon.ico'), 'icon path fixture; never rendered')
    [IO.File]::WriteAllText((Join-Path $runtime 'venv/Scripts/python.exe'), 'fixture; never executed')
    $shortcutPath = Join-Path $programs 'Hermes.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $pwsh
    $shortcut.Arguments = '-NoProfile -Command exit'
    $shortcut.Save()
    $originalHash = (Get-FileHash -LiteralPath $shortcutPath).Hash
    $launcher = Join-Path $root 'scripts/setup-windows-hermes-launcher.ps1'
    $options = @{ HermesHome=$runtimeHome; HermesRoot=$runtime; ProgramsDirectory=$programs; TaskbarDirectory=$taskbar }
    & $launcher @options | Out-Null
    if ((Get-FileHash $shortcutPath).Hash -ne $originalHash) { throw 'Preview changed shortcut' }
    $failed = $false
    try { & $launcher -Check @options | Out-Null } catch { $failed = $_.Exception.Message -match 'launcher differs' }
    if (-not $failed) { throw 'Drift check accepted packaged shortcut' }
    . (Join-Path $root 'scripts/lib/windows-shortcuts.ps1')
    $collisionPath = Join-Path $programs 'Electron.lnk'
    $bare = $shell.CreateShortcut($collisionPath)
    $bare.TargetPath = Join-Path $runtime 'apps/desktop/node_modules/electron/dist/electron.exe'
    $bare.Save()
    [Dotfiles.ShortcutIdentity]::Set($collisionPath, 'com.nousresearch.hermes')
    $collisionHash = (Get-FileHash $collisionPath).Hash
    $pin = Join-Path $taskbar 'Electron.lnk'
    Copy-Item -LiteralPath $collisionPath -Destination $pin
    $pinBefore = (Get-FileHash $pin).Hash
    & $launcher -Apply @options | Out-Null
    & $launcher -Check @options | Out-Null
    if ([Dotfiles.ShortcutIdentity]::Get($shortcutPath) -cne 'com.nousresearch.hermes') { throw 'Canonical Hermes app identity missing' }
    $pinned = $shell.CreateShortcut($pin)
    $managed = $shell.CreateShortcut($shortcutPath)
    if ($managed.IconLocation -ine ((Join-Path $runtime 'apps/desktop/assets/icon.ico')+',0')) { throw 'Source-only launch has no bundled Hermes icon' }
    if ($pinned.TargetPath -ine $managed.TargetPath -or $pinned.Arguments -cne $managed.Arguments -or $pinned.IconLocation -cne $managed.IconLocation) { throw 'Taskbar pin does not match managed Hermes launch and icon' }
    if ((Get-FileHash ($pin+'.before-dotfiles')).Hash -ne $pinBefore) { throw 'Taskbar backup missing or changed' }
    $pinAfter=(Get-FileHash $pin).Hash
    & $launcher -Apply @options | Out-Null
    if ((Get-FileHash $pin).Hash -ne $pinAfter) { throw 'Taskbar repair is not idempotent' }
    Copy-Item -LiteralPath ($pin+'.before-dotfiles') -Destination $pin -Force
    $failed=$false
    try { & $launcher -Check @options | Out-Null } catch { $failed=$true }
    if (-not $failed) { throw 'Taskbar drift was accepted' }
    & $launcher -Apply @options | Out-Null
    if (Test-Path $collisionPath) { throw 'Bare Electron identity remains active' }
    [Dotfiles.ShortcutIdentity]::Set($pin, '')
    $failed=$false
    try { & $launcher -Check @options | Out-Null } catch { $failed=$true }
    if (-not $failed) { throw 'Missing pinned identity was ignored' }
    & $launcher -Apply @options | Out-Null
    if ([Dotfiles.ShortcutIdentity]::Get($pin) -cne 'com.nousresearch.hermes') { throw 'Missing pinned identity not repaired' }
    [Dotfiles.ShortcutIdentity]::Set($pin, 'fixture.foreign')
    $failed=$false
    try { & $launcher -Apply @options | Out-Null } catch { $failed=$true }
    if (-not $failed) { throw 'Conflicting pinned identity was overwritten' }
    [Dotfiles.ShortcutIdentity]::Set($pin, 'com.nousresearch.hermes')
    foreach ($directory in @($programs,$taskbar)) { Set-Content (Join-Path $directory 'Unrelated-broken.lnk') 'broken fixture' }
    & $launcher -Check @options -WarningVariable warnings 3>$null | Out-Null
    if (@($warnings).Count -ne 2) { throw 'Unreadable unrelated shortcuts not reported' }
    if ((Get-FileHash ($collisionPath+'.before-dotfiles')).Hash -ne $collisionHash) { throw 'Electron collision backup changed' }
    Copy-Item -LiteralPath ($collisionPath+'.before-dotfiles') -Destination $collisionPath
    $failed=$false
    try { & $launcher -Check @options | Out-Null } catch { $failed=$true }
    if (-not $failed) { throw 'Recreated identity conflict was accepted' }
    & $launcher -Apply @options | Out-Null
    if ((Get-FileHash ($collisionPath+'.before-dotfiles')).Hash -ne $collisionHash) { throw 'Repeated repair replaced original backup' }
    $unrelated = $shell.CreateShortcut($collisionPath)
    $unrelated.TargetPath=$pwsh; $unrelated.Save()
    [Dotfiles.ShortcutIdentity]::Set($collisionPath, 'fixture.other')
    $unrelatedHash=(Get-FileHash $collisionPath).Hash
    & $launcher -Apply @options | Out-Null
    if ((Get-FileHash $collisionPath).Hash -ne $unrelatedHash) { throw 'Unrelated Electron shortcut modified' }
    [Dotfiles.ShortcutIdentity]::Set($collisionPath, 'com.nousresearch.hermes')
    $managedHash=(Get-FileHash $shortcutPath).Hash
    $failed=$false
    try { & $launcher -Apply @options | Out-Null } catch { $failed=$true }
    if (-not $failed -or (Get-FileHash $shortcutPath).Hash -ne $managedHash) { throw 'Foreign identity collision did not fail before writes' }
    [Dotfiles.ShortcutIdentity]::Set($collisionPath, 'fixture.other')
    $configured = (Get-FileHash $shortcutPath).Hash
    & $launcher -Apply @options | Out-Null
    if ((Get-FileHash $shortcutPath).Hash -ne $configured) { throw 'Repeated setup rewrote shortcut' }
    if ((Get-FileHash ($shortcutPath+'.before-dotfiles')).Hash -ne $originalHash) { throw 'Original shortcut backup differs' }
    $shortcut = $shell.CreateShortcut($shortcutPath)
    if ($shortcut.TargetPath -ine $pwsh -or $shortcut.Arguments -notlike '*start-windows-hermes.ps1*' -or $shortcut.Arguments -notlike ('*-HermesHome "'+$runtimeHome+'"*')) { throw 'Shortcut target or quoted home is incorrect' }

    # Repair honors the environment; explicit paths and Python take precedence.
    $env:HERMES_HOME = $runtimeHome
    & $launcher -Check -ProgramsDirectory $programs -TaskbarDirectory $taskbar | Out-Null
    $alternatePython = Join-Path $fixture 'alternate python.exe'
    [IO.File]::WriteAllText($alternatePython, 'fixture; never executed')
    $env:HERMES_HOME = Join-Path $fixture 'unused environment home'
    & $launcher -Apply @options -Python $alternatePython | Out-Null
    & $launcher -Check @options -Python $alternatePython | Out-Null
    $shortcut = $shell.CreateShortcut($shortcutPath)
    if ($shortcut.Arguments -notlike ('*-Python "'+$alternatePython+'"*')) { throw 'Shortcut lost explicit Python' }
    if ((Get-FileHash ($shortcutPath+'.before-dotfiles')).Hash -ne $originalHash) { throw 'Runtime change overwrote original backup' }

    # Execute real wrappers with fake native commands and fake follow-up stages.
    $scripts = Join-Path $fixture 'scripts'
    [IO.Directory]::CreateDirectory((Join-Path $scripts 'lib')) | Out-Null
    foreach ($name in @('start-windows-hermes.ps1','update-windows-hermes.ps1')) {
        Copy-Item -LiteralPath (Join-Path $root "scripts/$name") -Destination (Join-Path $scripts $name)
    }
    $common = @'
function Assert-DotfilesWindows {}
function Assert-DotfilesPythonRuntime([string]$Path,[string]$Label) {
    if ($Label -ne 'Hermes Python') { throw 'Unexpected runtime probe label' }
    $global:PublicHermesFixtureState.runtimeCalls++
    if ($global:PublicHermesFixtureState.failRuntime) { throw 'fixture Application Control block' }
}
function Assert-DotfilesPreferenceFile([string]$Path) { if (-not (Test-Path -LiteralPath $Path)) { throw 'Fixture runtime missing' } }
function Invoke-DotfilesNativeUtf8([string]$File,[string[]]$Arguments) {
    $global:PublicHermesFixtureState.nativeCalls++
    $global:PublicHermesFixtureState.observedArguments = $Arguments
    $global:PublicHermesFixtureState.observedPython = $File
    if ($global:PublicHermesFixtureState.failNative) { throw 'fixture native failure (exit 2)' }
    Write-Output 'fixture native success'
}
function Invoke-DotfilesNative([string]$File,[string[]]$Arguments) {
    if ($File -cne $global:PublicHermesFixtureState.selectedPython) { throw 'Settings setup lost selected Python' }
}
function Get-CimInstance { @() }
function Test-Path {
    param([Alias('Path')][string]$LiteralPath, [string]$PathType)
    # Model an initialized shared collection without accessing the live profile.
    if ($LiteralPath -eq (Join-Path $HOME '.agents/skills')) { return $true }
    $options = @{LiteralPath=$LiteralPath}
    if ($PathType) { $options.PathType=$PathType }
    Microsoft.PowerShell.Management\Test-Path @options
}
'@
    $realCommon = [IO.File]::ReadAllText((Join-Path $root 'scripts/lib/windows-common.ps1'))
    [IO.File]::WriteAllText((Join-Path $scripts 'lib/windows-common.ps1'), $realCommon + [Environment]::NewLine + $common)
    [IO.File]::WriteAllText((Join-Path $scripts 'setup-windows-hermes-launcher.ps1'), 'param([switch]$Apply,[string]$HermesHome,[string]$HermesRoot,[string]$Python); if ($global:PublicHermesFixtureState.checkSelectedPython -and $Python -cne $global:PublicHermesFixtureState.selectedPython) { throw "Settings setup omitted launcher Python" }; $global:PublicHermesFixtureState.repairCalls++')
    [IO.File]::WriteAllText((Join-Path $scripts 'setup-windows-hermes.ps1'), 'param([switch]$Check,[string]$HermesHome); $global:PublicHermesFixtureState.checkCalls++')
    [IO.Directory]::CreateDirectory((Join-Path $runtime 'hermes_cli')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $runtime 'hermes_cli/main.py'), '# fixture')
    # Run actual settings orchestration with dummy native/config/launcher boundaries.
    Copy-Item -LiteralPath (Join-Path $root 'scripts/setup-windows-hermes.ps1') -Destination (Join-Path $scripts 'setup-selected-runtime.ps1')
    [IO.File]::WriteAllText((Join-Path $runtimeHome 'config.yaml'), '{}')
    $global:PublicHermesFixtureState.selectedPython=$alternatePython
    $global:PublicHermesFixtureState.checkSelectedPython=$true
    & (Join-Path $scripts 'setup-selected-runtime.ps1') -Apply -HermesHome $runtimeHome -HermesRoot $runtime -Python $alternatePython | Out-Null
    $global:PublicHermesFixtureState.checkSelectedPython=$false
    $global:PublicHermesFixtureState.nativeCalls=0; $global:PublicHermesFixtureState.repairCalls=0; $global:PublicHermesFixtureState.checkCalls=0; $global:PublicHermesFixtureState.failNative=$false
    & (Join-Path $scripts 'start-windows-hermes.ps1') -HermesHome $runtimeHome -HermesRoot $runtime | Out-Null
    if (($global:PublicHermesFixtureState.observedArguments -join ' ') -cne '-u -m hermes_cli.main desktop --source --skip-build') { throw 'Source launch invoked a build or incorrect command' }
    if ($env:HERMES_HOME -cne $runtimeHome -or $env:HERMES_DESKTOP_HERMES_ROOT -cne $runtime) { throw 'Source launch selected wrong runtime' }
    # Environment-only source launch selects the same profile; an explicit runtime wins.
    & (Join-Path $scripts 'start-windows-hermes.ps1') | Out-Null
    if ($env:HERMES_HOME -cne $runtimeHome -or $global:PublicHermesFixtureState.observedPython -ine (Join-Path $runtime 'venv/Scripts/python.exe')) { throw 'Source launch ignored HERMES_HOME' }
    $env:HERMES_HOME = Join-Path $fixture 'unused environment home'
    & (Join-Path $scripts 'start-windows-hermes.ps1') -HermesHome $runtimeHome -HermesRoot $runtime -Python $alternatePython | Out-Null
    if ($env:HERMES_HOME -cne $runtimeHome -or $global:PublicHermesFixtureState.observedPython -cne $alternatePython) { throw 'Source launch lost explicit profile/Python' }
    if (($global:PublicHermesFixtureState.observedArguments -join ' ') -cne '-u -m hermes_cli.main desktop --source --skip-build') { throw 'Custom runtime launch changed no-build command' }
    $global:PublicHermesFixtureState.nativeCalls=0
    $updater = Join-Path $scripts 'update-windows-hermes.ps1'
    & $updater -DryRun | Out-Null
    if ($global:PublicHermesFixtureState.nativeCalls -or $global:PublicHermesFixtureState.repairCalls -or $global:PublicHermesFixtureState.checkCalls) { throw 'Dry run performed work' }
    $global:PublicHermesFixtureState.failRuntime=$true
    $failed=$false
    try { & $updater | Out-Null } catch { $failed=$_.Exception.Message -match 'fixture Application Control block.*Log:' }
    if (!$failed -or $global:PublicHermesFixtureState.nativeCalls -or $global:PublicHermesFixtureState.repairCalls -or $global:PublicHermesFixtureState.checkCalls) { throw 'Blocked runtime ran update/follow-up actions or lost its diagnostic' }
    $global:PublicHermesFixtureState.failRuntime=$false
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
Write-Output 'PASS: public Hermes shortcut preview/drift/repair/backup/idempotence, custom homes/Python, setup forwarding, source arguments, update success/failure/dry-run and absent installation.'
