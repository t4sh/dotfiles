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

function Invoke-Stage {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [scriptblock] $Action
    )

    Write-Host "`n-> $Name"
    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
        $global:LASTEXITCODE = 0
        & $Action
        $status = $LASTEXITCODE
        if ($null -eq $status) { $status = 0 }
        if ($status -ne 0) { throw "exit $status" }
    } catch {
        $failed.Add("$Name ($($_.Exception.Message))")
        Write-Warning "$Name failed: $($_.Exception.Message). Continuing."
    } finally {
        Write-Host ("<- {0} ({1:n1}s)" -f $Name, $timer.Elapsed.TotalSeconds)
    }
}

if ($DryRun) {
    Write-Host 'Dry run previews Topgrade app/tool actions only; skill writes are skipped.'
    $SkipSkills = $true
}

if (-not $SkipApps) {
    Invoke-Stage -Name 'WinGet applications' -Action {
        & (Join-Path $PSScriptRoot 'install-windows-packages.ps1') -Upgrade -Apply:(-not $DryRun) -AllInstalled:$AllApps
    }

    Invoke-Stage -Name 'Topgrade apps and developer tools' -Action {
        $topgrade = Resolve-WinGetPackageCommand -Name 'topgrade' -PackagePattern 'topgrade-rs.topgrade'
        $arguments = @('--config', (Join-Path $dotfiles 'config\topgrade-windows.toml'))
        if ($DryRun) { $arguments += '--dry-run' }
        $previousCloudPython = $env:CLOUDSDK_PYTHON
        try {
            if (-not $DryRun -and (Get-Command gcloud.cmd -ErrorAction SilentlyContinue)) {
                $copied = @(& gcloud.cmd components copy-bundled-python)
                if ($LASTEXITCODE -ne 0) { throw 'gcloud could not prepare its update Python runtime.' }
                $cloudPython = @($copied | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
                if ($cloudPython.Count -ne 1) { throw 'gcloud did not return one valid update Python path.' }
                $env:CLOUDSDK_PYTHON = $cloudPython[0]
            }
            $topgradeLog = Join-Path $env:TEMP ('dotfiles-topgrade-' + [guid]::NewGuid().ToString('N') + '.log')
            Write-Host "Topgrade log: $topgradeLog"
            & $topgrade @arguments 2>&1 | Tee-Object -FilePath $topgradeLog
            if ($LASTEXITCODE -ne 0) {
                throw "Topgrade exited $LASTEXITCODE. Inspect FAILED entries and their preceding errors in $topgradeLog. Retry only the failed step with: topgrade --config `"$(Join-Path $dotfiles 'config/topgrade-windows.toml')`" --only <step> --verbose."
            }
        } finally { $env:CLOUDSDK_PYTHON = $previousCloudPython }
    }
    foreach ($editor in @('code','cursor')) {
        Invoke-Stage -Name "$editor extension policy" -Action {
            if ($DryRun) { Write-Output "Preview: reconcile $editor declared extension versions after Topgrade."; return }
            $extensionLog = Join-Path $env:TEMP "dotfiles-$editor-extensions.log"
            try { & (Join-Path $PSScriptRoot 'install-windows-extensions.ps1') -Editor $editor -Apply *> $extensionLog }
            catch { throw "Extension reconciliation failed: $($_.Exception.Message). Log: $extensionLog" }
        }
    }
    Invoke-Stage -Name 'Hermes' -Action {
        & (Join-Path $PSScriptRoot 'update-windows-hermes.ps1') -DryRun:$DryRun
    }
    Invoke-Stage -Name 'TLDR pages' -Action {
        & (Join-Path $PSScriptRoot 'update-windows-tldr.ps1') -DryRun:$DryRun
    }
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
            Write-Output 'Checking for skill updates...'
            Invoke-DotfilesNativeUtf8 $bash @((Join-Path $dotfiles 'Skillsfile')) | Where-Object { $_ -notmatch '^→ update ' }
            if ($LASTEXITCODE -ne 0) { throw "Skillsfile failed (exit $LASTEXITCODE)" }

            Invoke-DotfilesNativeUtf8 $python @((Join-Path $dotfiles 'scripts\gen-skillsfile.py')) >> $skillsLog 2>&1
            Invoke-DotfilesNativeUtf8 $python @((Join-Path $dotfiles 'agents\compareskills.py')) >> $skillsLog 2>&1
            Invoke-DotfilesNativeUtf8 $bash @((Join-Path $dotfiles 'scripts\audit-skill-licenses.sh'),'--check') >> $skillsLog 2>&1
            & (Join-Path $dotfiles 'scripts\setup-windows-skill-engine.ps1') -Apply >> $skillsLog 2>&1
            & git -C $dotfiles rev-parse --is-inside-work-tree *> $null
            if ($LASTEXITCODE -eq 0) {
                & git -C $dotfiles status --short -- Skillsfile agents/.skill-lock.json agents/skills agents/skills/README.md >> $skillsLog 2>&1
            } else {
                Write-Warning "$dotfiles is not a Git checkout; refreshed skills are local-only until this dotfiles copy is connected to its remote."
                $global:LASTEXITCODE = 0
            }
            Write-Output 'Skill refresh complete for accessible sources; any skipped sources are listed above.'
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
        & (Join-Path $dotfiles 'scripts\setup-windows-path.ps1')
    }
}

if ($failed.Count -gt 0) {
    throw "Windows maintenance finished with $($failed.Count) failed stage(s): $($failed -join '; ')"
}

Write-Host "`nWindows maintenance complete."
