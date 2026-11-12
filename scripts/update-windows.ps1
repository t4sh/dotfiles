#Requires -Version 7.0
[CmdletBinding()]
param(
    [switch] $DryRun,
    [switch] $SkipApps,
    [switch] $SkipSkills,
    [switch] $AllApps
)

$ErrorActionPreference = 'Stop'
$dotfiles = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'lib\windows-common.ps1')
Assert-DotfilesWindows
$failed = [Collections.Generic.List[string]]::new()

function Resolve-WinGetPackageCommand {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $PackagePattern
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $packages = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    $candidate = Get-ChildItem -LiteralPath $packages -Filter "$Name.exe" -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object FullName -Like "*$PackagePattern*" |
        Select-Object -First 1
    if ($candidate) { return $candidate.FullName }

    throw "$Name was not found. Install it with WinGet first."
}

function Resolve-Python { Resolve-DotfilesPython }
function Resolve-GitBash { Resolve-DotfilesBash }
function Resolve-Npx {
    $shim = Join-Path $HOME '.local\bin\npx-stable.cmd'
    if (-not (Test-Path -LiteralPath $shim)) { throw 'Run setup-windows-path.ps1 to create npx-stable.' }
    return $shim
}

function Get-DotfilesUpdateOutputColor {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [switch]$WarningContinuation)

    $line = $Text -replace '\x1B\[[0-?]*[ -/]*[@-~]', ''
    if ($WarningContinuation -or $line -match '(?i)\b(?:warning|warn|deprecationwarning)\b') { return [ConsoleColor]::Yellow }
    if ($line -match '(?i)\b(?:error|fatal|failed|failure|exception|traceback|denied|could not|cannot|not found|not recognized|unable to)\b') { return [ConsoleColor]::Red }
    if ($line -match '(?i)\bsuccess(?:fully)?\b|\ball components are up to date\b|\bchanged\s+\d+\s+packages?\s+in\b|\ball versions already on latest\b|\bproject mirrors synced\b|\bfixture:\s*ok\b') { return [ConsoleColor]::Green }
    if ($line -match '(?i)\b(?:info|beginning update|checking for updates?|update available|nothing to upgrade|no marketplaces configured|pruning cache|no unused entries|to update, run:)\b|^\s*--') { return [ConsoleColor]::Blue }
    return [ConsoleColor]::Blue
}

function Write-DotfilesUpdateOutput {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)] [object] $Record,
        [IO.StreamWriter] $LogWriter
    )
    begin { $warningContinuation = $false }
    process {
        $rawLine = if ($Record -is [Management.Automation.ErrorRecord]) { [string]$Record.Exception.Message }
            elseif ($Record -is [Management.Automation.WarningRecord]) { [string]$Record.Message }
            else { [string]$Record }
        $line = $rawLine -replace '\x1B\[[0-?]*[ -/]*[@-~]', ''
        if ($LogWriter) { $LogWriter.WriteLine($line) }
        $warningStart = ($Record -is [Management.Automation.WarningRecord]) -or ($line -match '(?i)\b(?:warning|warn|deprecationwarning)\b')
        $warningFollowOn = $warningContinuation -and ($line -match '^\s*(?:\(Use\b|CVEs?\b|behavior\b|implications\b)')
        $color = if ($Record -is [Management.Automation.WarningRecord]) { [ConsoleColor]::Yellow }
            else { Get-DotfilesUpdateOutputColor -Text $line -WarningContinuation:$warningFollowOn }
        Write-Host $line -ForegroundColor $color
        if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^\s*--') { $warningContinuation = $false }
        else { $warningContinuation = $warningStart -or $warningFollowOn }
    }
}

function Invoke-Stage {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [scriptblock] $Action
    )

    $stageFailed = $false
    Write-Host "`n-> $Name" -ForegroundColor Blue
    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
        $global:LASTEXITCODE = 0
        & $Action
        $status = $LASTEXITCODE
        if ($null -eq $status) { $status = 0 }
        if ($status -ne 0) { throw "exit $status" }
    } catch {
        $stageFailed = $true
        $failed.Add("$Name ($($_.Exception.Message))")
        Write-Host "$Name failed: $($_.Exception.Message). Continuing." -ForegroundColor Red
    } finally {
        $stageColor = if ($stageFailed) { [ConsoleColor]::Red } else { [ConsoleColor]::Green }
        Write-Host ("<- {0} ({1:n1}s)" -f $Name, $timer.Elapsed.TotalSeconds) -ForegroundColor $stageColor
    }
}

# Two runs share package state, skill files and logs. Serialize by Windows user.
$userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$maintenanceMutex = [Threading.Mutex]::new($false, "Global\DotfilesWindowsMaintenance-$userSid")
$ownsMutex = $false
try {
    try { $ownsMutex = $maintenanceMutex.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
    if (-not $ownsMutex) { throw 'Windows maintenance is already running for this user. Wait for it to finish before running update-all again.' }

    if ($DryRun) {
        Write-Host 'Dry run previews Topgrade app/tool actions only; skill writes are skipped.' -ForegroundColor Blue
        $SkipSkills = $true
    }
    if (-not $SkipApps) {
        Invoke-Stage -Name 'WinGet applications' -Action {
            & (Join-Path $PSScriptRoot 'install-windows-packages.ps1') -Upgrade -Apply:(-not $DryRun) -AllInstalled:$AllApps |
                Out-String -Stream |
                Write-DotfilesUpdateOutput
        }
        Invoke-Stage -Name 'Topgrade apps and developer tools' -Action {
            $topgrade = Resolve-WinGetPackageCommand -Name 'topgrade' -PackagePattern 'topgrade-rs.topgrade'
            $arguments = @('--config', (Join-Path $dotfiles 'config\topgrade-windows.toml'))
            if ($DryRun) { $arguments += '--dry-run' }
            $previousCloudPython = $env:CLOUDSDK_PYTHON
            $previousNoColor = $env:NO_COLOR
            $previousTopgradeEncoding = [Console]::OutputEncoding
            try {
                [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
                if (-not $DryRun -and (Get-Command gcloud.cmd -ErrorAction SilentlyContinue)) {
                    $copied = @(& gcloud.cmd components copy-bundled-python)
                    if ($LASTEXITCODE -ne 0) { throw 'gcloud could not prepare its update Python runtime.' }
                    $cloudPython = @($copied | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
                    if ($cloudPython.Count -ne 1) { throw 'gcloud did not return one valid update Python path.' }
                    $env:CLOUDSDK_PYTHON = $cloudPython[0]
                }
                $topgradeLog = Join-Path $env:TEMP ('dotfiles-topgrade-' + [guid]::NewGuid().ToString('N') + '.log')
                Write-Host "Topgrade log: $topgradeLog" -ForegroundColor Blue
                $env:NO_COLOR = '1'
                $topgradeLogWriter = [IO.StreamWriter]::new($topgradeLog, $false, [Text.UTF8Encoding]::new($false))
                $topgradeLogWriter.AutoFlush = $true
                try {
                    & $topgrade @arguments 2>&1 | Write-DotfilesUpdateOutput -LogWriter $topgradeLogWriter
                } catch {
                    for ($cause = $_.Exception; $null -ne $cause; $cause = $cause.InnerException) {
                        if ($cause -is [ComponentModel.Win32Exception] -and $cause.NativeErrorCode -eq 4551) {
                            $message = "Windows Application Control blocked Topgrade at '$topgrade' (Win32 4551). Use a Topgrade build permitted by your policy. Code Integrity event 3077 can identify the blocked file. Log: $topgradeLog"
                            $topgradeLogWriter.WriteLine($message)
                            throw $message
                        }
                    }
                    throw
                } finally {
                    $topgradeLogWriter.Dispose()
                }
                if ($LASTEXITCODE -ne 0) {
                    throw "Topgrade exited $LASTEXITCODE. Inspect FAILED entries and their preceding errors in $topgradeLog. Retry only the failed step with: topgrade --config `"$(Join-Path $dotfiles 'config/topgrade-windows.toml')`" --only <step> --verbose."
                }
            } finally {
                $env:CLOUDSDK_PYTHON = $previousCloudPython
                $env:NO_COLOR = $previousNoColor
                [Console]::OutputEncoding = $previousTopgradeEncoding
            }
        }
        foreach ($editor in @('code','cursor')) {
            Invoke-Stage -Name "$editor extension policy" -Action {
                if ($DryRun) { Write-Host "Preview: reconcile $editor declared extension versions after Topgrade." -ForegroundColor Blue; return }
                $extensionLog = Join-Path $env:TEMP "dotfiles-$editor-extensions.log"
                try { & (Join-Path $PSScriptRoot 'install-windows-extensions.ps1') -Editor $editor -Apply *> $extensionLog }
                catch { throw "Extension reconciliation failed: $($_.Exception.Message). Log: $extensionLog" }
            }
        }
        Invoke-Stage -Name 'TLDR pages' -Action {
            & (Join-Path $PSScriptRoot 'update-windows-tldr.ps1') -DryRun:$DryRun
        }
        # Paused while Application Control rejects Hermes's managed Python (#99590).
        # Keep the standalone updater available for deliberate testing.
        Write-Host 'Hermes: excluded from Windows maintenance (runtime blocked; see WINDOWS.md).' -ForegroundColor Blue
    }
    if (-not $SkipSkills) {
        Invoke-Stage -Name 'Repo-managed agent skills' -Action {
            $skillsLog = Join-Path $env:TEMP 'dotfiles-skills-checks.log'
            try { & (Join-Path $dotfiles 'scripts\check-windows-skills.ps1') *> $skillsLog }
            catch { throw "Skills preflight failed: $($_.Exception.Message). Checks log: $skillsLog" }
            $bash = Resolve-GitBash
            $python = Resolve-Python
            $npxReal = Resolve-Npx
            $npxWrapper = Join-Path $dotfiles 'scripts\npx-skills-windows.cmd'
            $oldNpx = $env:NPX
            $oldNpxReal = $env:NPX_REAL
            $oldPythonBin = $env:PYTHON_BIN
            try {
                # Explicitly target Codex so the current skills CLI does not append
                # its unsupported global PromptScript target (vercel-labs/skills#1496).
                $env:NPX = $npxWrapper
                $env:NPX_REAL = $npxReal
                # Git Bash otherwise finds the Windows Store python alias first.
                $env:PYTHON_BIN = $python
                Write-Host 'Checking for skill updates...' -ForegroundColor Blue
                Invoke-DotfilesNativeUtf8 $bash @((Join-Path $dotfiles 'Skillsfile')) 2>&1 |
                    Where-Object { $_ -notmatch '^→ update ' } |
                    Write-DotfilesUpdateOutput
                if ($LASTEXITCODE -ne 0) { throw "Skillsfile failed (exit $LASTEXITCODE)" }
                Invoke-DotfilesNativeUtf8 $python @((Join-Path $dotfiles 'scripts\gen-skillsfile.py')) >> $skillsLog 2>&1
                Invoke-DotfilesNativeUtf8 $python @((Join-Path $dotfiles 'agents\compareskills.py')) >> $skillsLog 2>&1
                Invoke-DotfilesNativeUtf8 $bash @((Join-Path $dotfiles 'scripts\audit-skill-licenses.sh'),'--check') >> $skillsLog 2>&1
                & (Join-Path $dotfiles 'scripts\setup-windows-skill-engine.ps1') -Apply >> $skillsLog 2>&1
                & git -C $dotfiles rev-parse --is-inside-work-tree *> $null
                if ($LASTEXITCODE -eq 0) {
                    & git -C $dotfiles status --short -- Skillsfile agents/.skill-lock.json agents/skills agents/skills/README.md >> $skillsLog 2>&1
                } else {
                    Write-Host "$dotfiles is not a Git checkout; refreshed skills are local-only until this dotfiles copy is connected to its remote." -ForegroundColor Blue
                    $global:LASTEXITCODE = 0
                }
                Write-Host 'Skill refresh complete for accessible sources; any skipped sources are listed above.' -ForegroundColor Green
            } catch {
                throw "Skill refresh failed: $($_.Exception.Message). Checks log: $skillsLog"
            } finally {
                $env:NPX = $oldNpx
                $env:NPX_REAL = $oldNpxReal
                $env:PYTHON_BIN = $oldPythonBin
            }
        }
    }
    if (-not $DryRun) {
        Invoke-Stage -Name 'Windows command paths' -Action {
            & (Join-Path $dotfiles 'scripts\setup-windows-path.ps1') |
                Out-String -Stream |
                Write-DotfilesUpdateOutput
        }
    }
    if ($failed.Count -gt 0) {
        throw "Windows maintenance finished with $($failed.Count) failed stage(s): $($failed -join '; ')"
    }
    Write-Host "`nWindows maintenance complete." -ForegroundColor Green
} finally {
    if ($ownsMutex) { $maintenanceMutex.ReleaseMutex() }
    $maintenanceMutex.Dispose()
}
