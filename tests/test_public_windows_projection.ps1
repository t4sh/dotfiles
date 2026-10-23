#Requires -Version 7.4
# Public-owned fixtures for projection-specific Windows behavior.
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) {
    Write-Output 'SKIP: public Windows projection fixtures require native Windows.'
    exit 0
}

$root = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('public-projection-' + [guid]::NewGuid().ToString('N'))

function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

try {
    # Exercise the package manifest contract against disposable Brewfile data.
    $packageRoot = Join-Path $fixture 'packages'
    $config = Join-Path $packageRoot 'config'
    New-Item -ItemType Directory -Path $fixture -Force | Out-Null
    New-Item -ItemType Directory -Path $config -Force | Out-Null
    $encoding = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText((Join-Path $packageRoot 'Brewfile'), 'brew "fixture-mapped"' + "`n", $encoding)
    $header = "Key`tMode`tSource`tId`tNote`n"
    $rows = @(
        "brew:fixture-mapped`tmanual`t`t`tFixture disposition`n",
        "windows:rsync`tmanual`t`t`tManual WSL disposition`n"
    ) -join ''
    $manifest = Join-Path $config 'windows-packages.tsv'
    [IO.File]::WriteAllText($manifest, $header + $rows, $encoding)

    . (Join-Path $root 'scripts/lib/windows-packages.ps1')
    $publicPackages = @(Get-DotfilesWindowsPackages -Root $root)
    $publicRsync = @($publicPackages | Where-Object Key -EQ 'windows:rsync')
    Assert ($publicRsync.Count -eq 1 -and $publicRsync[0].Mode -eq 'manual') 'The public package manifest must retain its manual windows:rsync disposition.'
    $packages = @(Get-DotfilesWindowsPackages -Root $packageRoot)
    $rsync = @($packages | Where-Object Key -EQ 'windows:rsync')
    Assert ($rsync.Count -eq 1 -and $rsync[0].Mode -eq 'manual') 'The explicit windows:rsync manual disposition was rejected.'

    # Deskflow version policy and the real installer wiring use only disposable
    # manifests and a WinGet function mock; no live pins or processes are touched.
    $deskflowVersionRows = @(Get-DotfilesListedWinGetVersions @('Version','-------','1.27.0.10','1.27.0','1.26.0','1.25.0'))
    Assert ($deskflowVersionRows.Count -eq 4) 'Deskflow mixed stable/continuous version output was not parsed.'
    Assert ((Get-DotfilesLatestStableWinGetVersion $deskflowVersionRows) -ceq '1.27.0') 'Deskflow latest stable selection included a continuous build.'
    Assert ((Get-DotfilesInstallableDeskflowVersion $deskflowVersionRows) -ceq '1.26.0') 'Deskflow selection did not skip blocked stable 1.27.0.'
    Assert ((Convert-DotfilesInstalledWinGetVersion '1.26.0.0') -ceq '1.26.0') 'Deskflow MSI stable version was not normalized.'
    Assert ((Convert-DotfilesInstalledWinGetVersion '1.26.0.10') -ceq '1.26.0.10') 'Deskflow continuous version was incorrectly normalized.'
    Assert (-not (Test-DotfilesDeskflowRequiresReplacement '' '1.26.0')) 'Absent Deskflow should not be replaced.'
    Assert (-not (Test-DotfilesDeskflowRequiresReplacement '1.26.0' '1.26.0')) 'Current Deskflow should not be replaced.'
    Assert (-not (Test-DotfilesDeskflowRequiresReplacement '1.25.0' '1.26.0')) 'Older stable Deskflow should use normal upgrade.'
    Assert (Test-DotfilesDeskflowRequiresReplacement '1.27.0' '1.26.0') 'Blocked newer Deskflow stable should be replaced.'
    Assert (Test-DotfilesDeskflowRequiresReplacement '1.27.0.10' '1.26.0') 'Deskflow continuous build should be replaced.'

    $global:DeskflowExpectedPin = 'pin add --id Deskflow.Deskflow --exact --source winget --version 1.26.0 --force --accept-source-agreements --disable-interactivity'
    $global:DeskflowState = $null
    function winget.exe {
        $words = @($args | ForEach-Object { [string]$_ })
        $global:DeskflowState.Calls.Add(($words -join ' '))
        if ($words.Count -ge 2 -and ($words[0..1] -join ' ') -ceq 'pin add') {
            if (($words -join ' ') -cne $global:DeskflowExpectedPin) { throw 'Deskflow used unexpected pin arguments.' }
            $global:LASTEXITCODE = [int]$global:DeskflowState.PinExit
            if ($global:LASTEXITCODE -eq 0) { $global:DeskflowState.Pinned = '1.26.0' }
            return
        }
        if ($words[0] -ceq 'show') {
            $global:LASTEXITCODE = 0
            return @('Version','-------','1.27.0.10','1.27.0','1.26.0','1.25.0')
        }
        if ($words[0] -ceq 'export') {
            $outputIndex = [array]::IndexOf($words, '--output')
            if ($outputIndex -lt 0) { throw 'Deskflow inventory export omitted --output.' }
            $packagesForExport = @()
            if ($global:DeskflowState.Installed) {
                $packagesForExport = @(@{ PackageIdentifier='Deskflow.Deskflow'; Version=[string]$global:DeskflowState.Installed })
            }
            $inventory = @{ Sources=@(@{ SourceDetails=@{ Name='winget' }; Packages=$packagesForExport }) }
            [IO.File]::WriteAllText($words[$outputIndex + 1], ($inventory | ConvertTo-Json -Depth 6 -Compress), $encoding)
            $global:LASTEXITCODE = 0
            return
        }
        if ($words[0] -ceq 'uninstall') {
            $global:DeskflowState.Installed = ''
            $global:LASTEXITCODE = 0
            return
        }
        if ($words[0] -in @('install','upgrade')) {
            $versionIndex = [array]::IndexOf($words, '--version')
            if ($versionIndex -ge 0) { $global:DeskflowState.Installed = $words[$versionIndex + 1] }
            $global:LASTEXITCODE = 0
            return
        }
        throw "Unexpected mocked WinGet operation: $($words -join ' ')"
    }
    function Get-Service { return $null }
    function Get-Process { return @() }
    try {
        $deskflowRoot = Join-Path $fixture 'deskflow'
        $deskflowScripts = Join-Path $deskflowRoot 'scripts'
        $deskflowLib = Join-Path $deskflowScripts 'lib'
        New-Item -ItemType Directory -Path $deskflowLib -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $root 'scripts/install-windows-packages.ps1') -Destination $deskflowScripts
        Copy-Item -LiteralPath (Join-Path $root 'scripts/lib/windows-packages.ps1') -Destination $deskflowLib
        Copy-Item -LiteralPath (Join-Path $root 'scripts/lib/windows-app-groups.ps1') -Destination $deskflowLib
        Copy-Item -LiteralPath (Join-Path $root 'scripts/lib/windows-tldr.ps1') -Destination $deskflowLib
        [IO.File]::WriteAllText((Join-Path $deskflowLib 'windows-common.ps1'), @'
function Assert-DotfilesWindows {}
function Invoke-DotfilesNative {
    param([string]$Executable,[string[]]$Arguments,[int[]]$AllowedExitCodes=@(0))
    & $Executable @Arguments
    if ($LASTEXITCODE -notin $AllowedExitCodes) { throw "Fixture native command failed (exit $LASTEXITCODE)." }
}
'@, $encoding)
        [IO.File]::WriteAllText((Join-Path $deskflowRoot 'Brewfile'), 'cask "deskflow/tap/deskflow"' + "`n", $encoding)
        $deskflowConfig = Join-Path $deskflowRoot 'config'
        New-Item -ItemType Directory -Path $deskflowConfig -Force | Out-Null
        $deskflowManifest = "Key`tMode`tSource`tId`tNote`n" + "cask:deskflow/tap/deskflow`tnative`twinget`tDeskflow.Deskflow`tFixture disposition`n"
        [IO.File]::WriteAllText((Join-Path $deskflowConfig 'windows-packages.tsv'), $deskflowManifest, $encoding)
        [IO.File]::WriteAllText((Join-Path $deskflowConfig 'app-groups.tsv'), "Key`tGroup`ncask:deskflow/tap/deskflow`tessentials`n", $encoding)
        $global:DeskflowInstaller = Join-Path $deskflowScripts 'install-windows-packages.ps1'
        $global:DeskflowFixtureRoot = $deskflowRoot

        function Invoke-PublicDeskflowInstallFixture {
            param([string]$Label,[string]$InitialVersion,[string[]]$Arguments)
            $global:DeskflowState = [pscustomobject]@{ Installed=$InitialVersion; PinExit=0; Pinned='1.25.0'; Calls=[Collections.Generic.List[string]]::new() }
            $installerParameters = @{
                Apply = $Arguments -contains '-Apply'
                Upgrade = $Arguments -contains '-Upgrade'
                AllInstalled = $Arguments -contains '-AllInstalled'
                LogDirectory = Join-Path $global:DeskflowFixtureRoot "logs/$Label"
            }
            if (-not $installerParameters.AllInstalled) { $installerParameters.Only = @('Deskflow.Deskflow') }
            & $global:DeskflowInstaller @installerParameters
            Assert ($LASTEXITCODE -eq 0) "Deskflow installer fixture '$Label' failed."
            return $global:DeskflowState.Calls.ToArray()
        }

        $global:DeskflowState = [pscustomobject]@{ Installed='1.26.0'; PinExit=0; Pinned='1.25.0'; Calls=[Collections.Generic.List[string]]::new() }
        Set-DotfilesDeskflowStablePin '1.26.0'
        Set-DotfilesDeskflowStablePin '1.26.0'
        Assert ($global:DeskflowState.Pinned -ceq '1.26.0') 'Repeated Deskflow pin repair did not converge.'
        Assert ($global:DeskflowState.Calls.Count -eq 2 -and @($global:DeskflowState.Calls | Where-Object { $_ -cne $global:DeskflowExpectedPin }).Count -eq 0) 'Repeated Deskflow pin repair did not use the exact forced-pin arguments.'
        $global:DeskflowState.PinExit = 17
        $pinFailurePropagated = $false
        try { Set-DotfilesDeskflowStablePin '1.26.0' } catch { $pinFailurePropagated = $_.Exception.Message -like '*exit 17*' }
        Assert $pinFailurePropagated 'Deskflow native pin failure was not propagated.'

        $installCalls = @(Invoke-PublicDeskflowInstallFixture -Label 'install' -InitialVersion '' -Arguments @('-Apply','-Only','Deskflow.Deskflow'))
        Assert ($global:DeskflowState.Installed -ceq '1.26.0') 'Deskflow install did not select the allowed stable version.'
        Assert (@($installCalls | Where-Object { $_ -like 'install --id Deskflow.Deskflow *--version 1.26.0 *--no-upgrade' }).Count -eq 1) 'The real Deskflow install path omitted the selected version.'

        $noopCalls = @(Invoke-PublicDeskflowInstallFixture -Label 'already-current' -InitialVersion '1.26.0' -Arguments @('-Apply','-Only','Deskflow.Deskflow'))
        Assert (@($noopCalls | Where-Object { $_ -match '^(install|upgrade|uninstall) --id Deskflow\.Deskflow' }).Count -eq 0) 'Current Deskflow was unnecessarily reinstalled.'

        $replaceCalls = @(Invoke-PublicDeskflowInstallFixture -Label 'continuous-replacement' -InitialVersion '1.27.0.10' -Arguments @('-Apply','-Only','Deskflow.Deskflow'))
        Assert ($global:DeskflowState.Installed -ceq '1.26.0') 'Continuous Deskflow was not replaced by the allowed stable version.'
        Assert (@($replaceCalls | Where-Object { $_ -like 'uninstall --id Deskflow.Deskflow *' }).Count -eq 1 -and @($replaceCalls | Where-Object { $_ -like 'install --id Deskflow.Deskflow *--version 1.26.0*' }).Count -eq 1) 'Deskflow replacement did not uninstall then install the allowed version.'

        $upgradeCalls = @(Invoke-PublicDeskflowInstallFixture -Label 'upgrade-older-stable' -InitialVersion '1.25.0' -Arguments @('-Apply','-Upgrade','-Only','Deskflow.Deskflow'))
        Assert ($global:DeskflowState.Installed -ceq '1.26.0') 'Deskflow normal upgrade did not select the allowed stable version.'
        Assert (@($upgradeCalls | Where-Object { $_ -like 'upgrade --id Deskflow.Deskflow *--version 1.26.0*' }).Count -eq 1) 'Deskflow normal upgrade path omitted the selected version.'

        $allUpgradeCalls = @(Invoke-PublicDeskflowInstallFixture -Label 'all-upgrade' -InitialVersion '1.26.0' -Arguments @('-Apply','-Upgrade','-AllInstalled'))
        $pinCallIndex = [array]::IndexOf([string[]]$allUpgradeCalls, $global:DeskflowExpectedPin)
        $allUpgradeIndex = [array]::FindIndex([string[]]$allUpgradeCalls, [Predicate[string]]{ param($call) $call -like 'upgrade --all *' })
        Assert ($pinCallIndex -ge 0 -and $allUpgradeIndex -gt $pinCallIndex) 'The update-all path did not set the stable Deskflow pin before upgrade --all.'
        Assert (-not (Test-Path -LiteralPath (Join-Path $root 'apps/windows/extra/deskflow/settings.json'))) 'Machine-specific Deskflow settings entered the public tree.'
    } finally {
        Remove-Item Function:\winget.exe -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-Service -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-Process -ErrorAction SilentlyContinue
        Remove-Item Function:\Invoke-PublicDeskflowInstallFixture -ErrorAction SilentlyContinue
        Remove-Variable DeskflowState,DeskflowExpectedPin,DeskflowInstaller,DeskflowFixtureRoot -Scope Global -ErrorAction SilentlyContinue
    }

    # A failed prerequisite reports progress and a retry without starting any
    # later install or touching the host. All inputs live under the fixture.
    $entryRoot = Join-Path $fixture 'bootstrap-entry'
    $entryLib = Join-Path $entryRoot 'scripts/lib'
    New-Item -ItemType Directory -Path $entryLib,(Join-Path $entryRoot '.git'),(Join-Path $entryRoot 'config') -Force | Out-Null
    Copy-Item (Join-Path $root 'install.ps1') (Join-Path $entryRoot 'install.ps1')
    Copy-Item (Join-Path $root 'scripts/lib/windows-app-groups.ps1') (Join-Path $entryLib 'windows-app-groups.ps1')
    [IO.File]::WriteAllText((Join-Path $entryRoot 'Brewfile'), "cask `"fixture-app`"`n", $encoding)
    [IO.File]::WriteAllText((Join-Path $entryRoot 'config/app-groups.tsv'), "Key`tGroup`ncask:fixture-app`tessentials`n", $encoding)
    [IO.File]::WriteAllText((Join-Path $entryLib 'windows-packages.ps1'), 'function Get-DotfilesWindowsPackages { param($Root); @() }', $encoding)
    [IO.File]::WriteAllText((Join-Path $entryLib 'windows-common.ps1'), 'function Assert-DotfilesWindows {}; function Assert-DotfilesPersistentScriptPolicy {}; function Get-Command { param($Name,$ErrorAction); $null }; function Resolve-DotfilesPwsh { throw "fixture missing runtime" }; function Invoke-DotfilesNative { throw "fixture dependency failure" }', $encoding)
    $entryOutput = [Collections.Generic.List[string]]::new()
    $entryFailure = ''
    try { & (Join-Path $entryRoot 'install.ps1') -Apply | ForEach-Object { $entryOutput.Add([string]$_) } }
    catch { $entryFailure = $_.Exception.Message }
    Assert ($entryFailure -eq 'fixture dependency failure' -and $entryOutput -like 'Completed: persistent script policy*' -and $entryOutput -like 'Failed: dependency Microsoft.PowerShell*' -and $entryOutput -like 'Retry: winget install --id Microsoft.PowerShell*') 'Early bootstrap failure lost its progress report or original error.'

    [IO.File]::WriteAllText((Join-Path $packageRoot 'Brewfile'), "brew `"fixture-mapped`"`nbrew `"fixture-unmapped`"`n", $encoding)
    $unmappedRejected = $false
    try { Get-DotfilesWindowsPackages -Root $packageRoot | Out-Null }
    catch { $unmappedRejected = $_.Exception.Message -like '*Unmapped Brewfile entry: brew:fixture-unmapped*' }
    Assert $unmappedRejected 'An unmapped Brewfile entry was accepted.'

    # Exercise real dispatch with a process spy; never launch Settings or touch
    # the host's file associations from a fixture.
    $mediaScripts = Join-Path $fixture 'media/scripts'
    New-Item -ItemType Directory -Path (Join-Path $mediaScripts 'lib') -Force | Out-Null
    foreach ($name in @('dot-windows.ps1', 'check-windows-vlc-associations.ps1')) {
        Copy-Item (Join-Path $root "scripts/$name") (Join-Path $mediaScripts $name)
    }
    [IO.File]::WriteAllText((Join-Path $mediaScripts 'lib/windows-common.ps1'), @'
function Assert-DotfilesWindows {}
function Resolve-DotfilesPwsh { 'fixture-pwsh' }
function Invoke-DotfilesNative($Executable, $Arguments) { $global:PublicMediaArguments = $Arguments }
'@, $encoding)
    & (Join-Path $mediaScripts 'dot-windows.ps1') -Command default-apps -Arguments @('-Check')
    Assert ($global:PublicMediaArguments[-1] -eq '-Check') 'The media command lost its Check switch.'
    Assert ($global:PublicMediaArguments[-2] -eq (Join-Path (Split-Path $mediaScripts) 'scripts/check-windows-vlc-associations.ps1')) 'The media command selected the wrong helper.'
    Remove-Variable PublicMediaArguments -Scope Global

    $mediaManifest = Join-Path $fixture 'media.tsv'
    foreach ($case in @(
        @{Text="extension`n.mp4`n.mp4`n"; Error='Invalid or duplicate VLC extension:*'},
        @{Text="extension`n../mp4`n"; Error='Invalid or duplicate VLC extension:*'},
        @{Text="extension`n"; Error='VLC association manifest is empty.'}
    )) {
        [IO.File]::WriteAllText($mediaManifest, $case.Text, $encoding)
        $rejected = $false
        try { & (Join-Path $mediaScripts 'check-windows-vlc-associations.ps1') -Manifest $mediaManifest -Check | Out-Null }
        catch { $rejected = $_.Exception.Message -like $case.Error }
        Assert $rejected 'An invalid media manifest reached association inspection.'
    }

    # Extract the actual doctor check, stub its two read-only Git results, and
    # hide the launcher from command discovery.
    $tokens = $null
    $parseErrors = $null
    $doctorPath = Join-Path $root 'scripts/doctor-windows.ps1'
    $doctorAst = [Management.Automation.Language.Parser]::ParseFile($doctorPath, [ref]$tokens, [ref]$parseErrors)
    Assert ($parseErrors.Count -eq 0) 'The public Windows doctor does not parse.'
    $doctorCheck = $doctorAst.Find({ param($node)
        $node -is [Management.Automation.Language.CommandAst] -and
        $node.GetCommandName() -eq 'Check-Dotfiles' -and
        $node.CommandElements[1].Value -eq 'Windows Git overlay'
    }, $true)
    Assert ($null -ne $doctorCheck) 'The Windows Git overlay doctor check was not found.'
    $checkBlock = ($doctorCheck.CommandElements | Where-Object {
        $_ -is [Management.Automation.Language.ScriptBlockExpressionAst]
    } | Select-Object -First 1).ScriptBlock
    $checkText = $checkBlock.Extent.Text
    $checkText = $checkText.Replace(
        '$helper = & git.exe config --global --includes --get credential.helper',
        '$helper = ''manager''; $global:LASTEXITCODE = 0'
    )
    $checkText = $checkText.Replace(
        '$ssh = & git.exe config --global --includes --get core.sshCommand',
        '$ssh = ''dotfiles-ssh.cmd''; $global:LASTEXITCODE = 0'
    )
    Assert ($checkText -notmatch 'git\.exe') 'The doctor fixture would invoke the host Git configuration.'
    $checkText = $checkText.Trim()
    if (-not $checkText.StartsWith('{') -or -not $checkText.EndsWith('}')) {
        throw 'The parsed doctor check did not have the expected script-block extent.'
    }
    $checkText = $checkText.Substring(1, $checkText.Length - 2)
    $check = [scriptblock]::Create($checkText)

    function Get-Command {
        [CmdletBinding()]
        param([Parameter(Position = 0)][string]$Name)
        if ($Name -eq 'dotfiles-ssh.cmd') { return $null }
        Microsoft.PowerShell.Core\Get-Command -Name $Name -ErrorAction $ErrorActionPreference
    }

    $doctorMessage = ''
    try { & $check }
    catch { $doctorMessage = $_.Exception.Message }
    foreach ($required in @('dotfiles-ssh.cmd', '%USERPROFILE%\.local\bin', 'Machine-only PATH', 'dot path')) {
        Assert ($doctorMessage.Contains($required)) "The missing-launcher diagnostic omitted '$required'."
    }

    # Remove the doctor-only mock so TLDR exercises real command resolution.
    Remove-Item -LiteralPath Function:Get-Command

    # Command resolution must fail closed with the same diagnostic as process
    # start failure. The supplied path is intentionally absent, so no process runs.
    . (Join-Path $root 'scripts/lib/windows-tldr.ps1')
    $missingExecutable = Join-Path $fixture 'missing/tldr-python.exe'
    $tldrMessage = ''
    try { Invoke-DotfilesTldrProcess -Argument '--version' -Executable $missingExecutable | Out-Null }
    catch { $tldrMessage = $_.Exception.Message }
    Assert ($tldrMessage -like 'TLDR launch failed:*') 'A missing TLDR executable did not report TLDR launch failed.'
    Assert ($tldrMessage.Contains($missingExecutable)) 'TLDR did not fail on the intended absent executable.'

    function Invoke-PublicProjectionChild {
        param([Parameter(Mandatory)][string]$ScriptPath)
        & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File $ScriptPath
        if ($LASTEXITCODE -ne 0) { throw "Public projection child failed with exit $LASTEXITCODE." }
    }
    $failingChild = Join-Path $fixture 'expected-child-failure.ps1'
    [IO.File]::WriteAllText($failingChild, 'exit 23' + "`n", $encoding)
    $childFailurePropagated = $false
    try { Invoke-PublicProjectionChild -ScriptPath $failingChild }
    catch { $childFailurePropagated = $_.Exception.Message -like '*exit 23*' }
    Assert $childFailurePropagated 'The projection runner did not propagate a child fixture failure.'

    $vlcFixture = Join-Path $root 'tests/test_windows_vlc_associations.ps1'
    if (-not (Test-Path -LiteralPath $vlcFixture -PathType Leaf)) { throw 'VLC association-resolution fixture is missing.' }
    Invoke-PublicProjectionChild -ScriptPath $vlcFixture
    Invoke-PublicProjectionChild -ScriptPath (Join-Path $root 'tests/test_paseo_retirement.ps1')
    Invoke-PublicProjectionChild -ScriptPath (Join-Path $root 'tests/test_windows_app_groups.ps1')
    Write-Output 'PASS: Deskflow policy and installer wiring, app groups, bootstrap prerequisite reporting, package coverage, VLC dispatch/input rejection/resolution, doctor PATH guidance, TLDR failure, and child exit propagation.'
} finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if ((Split-Path $resolvedFixture -Parent) -ine $tempRoot -or (Split-Path $resolvedFixture -Leaf) -notmatch '^public-projection-[0-9a-f]{32}$') {
        throw 'Unsafe public projection fixture cleanup path.'
    }
    if (Test-Path -LiteralPath $resolvedFixture) { Remove-Item -LiteralPath $resolvedFixture -Recurse -Force }
}
