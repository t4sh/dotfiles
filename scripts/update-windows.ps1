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
    try {
        $global:LASTEXITCODE = 0
        & $Action
        $status = $LASTEXITCODE
        if ($null -eq $status) { $status = 0 }
        if ($status -ne 0) { throw "exit $status" }
    } catch {
        $failed.Add("$Name ($($_.Exception.Message))")
        Write-Warning "$Name failed: $($_.Exception.Message). Continuing."
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
        & $topgrade @arguments
    }
    Invoke-Stage -Name 'TLDR pages' -Action {
        & (Join-Path $PSScriptRoot 'update-windows-tldr.ps1') -DryRun:$DryRun
    }
}

if (-not $SkipSkills) {
    Invoke-Stage -Name 'Repo-managed agent skills' -Action {
        & (Join-Path $dotfiles 'scripts\check-windows-skills.ps1')
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
            & $bash (Join-Path $dotfiles 'Skillsfile')
            if ($LASTEXITCODE -ne 0) { throw "Skillsfile failed (exit $LASTEXITCODE)" }

            & $python (Join-Path $dotfiles 'scripts\gen-skillsfile.py')
            if ($LASTEXITCODE -ne 0) { throw "skills manifest generation failed (exit $LASTEXITCODE)" }
            & $python (Join-Path $dotfiles 'agents\compareskills.py')
            if ($LASTEXITCODE -ne 0) { throw "skills README generation failed (exit $LASTEXITCODE)" }
            & $bash (Join-Path $dotfiles 'scripts\audit-skill-licenses.sh') --check
            if ($LASTEXITCODE -ne 0) { throw "skill license audit failed (exit $LASTEXITCODE)" }
            & (Join-Path $dotfiles 'scripts\setup-windows-skill-engine.ps1') -Apply
            & git -C $dotfiles rev-parse --is-inside-work-tree *> $null
            if ($LASTEXITCODE -eq 0) {
                & git -C $dotfiles status --short -- Skillsfile agents/.skill-lock.json agents/skills agents/skills/README.md
            } else {
                Write-Warning "$dotfiles is not a Git checkout; refreshed skills are local-only until this dotfiles copy is connected to its remote."
                $global:LASTEXITCODE = 0
            }
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
