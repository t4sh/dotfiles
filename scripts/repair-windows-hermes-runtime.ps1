#Requires -Version 7.4
<#
.SYNOPSIS
Restore an executable Hermes venv interpreter after Application Control rejects
uv's generated launcher.

.DESCRIPTION
PM-managed installations are verified through their official launcher and
bootstrap. Their interpreter and dependency files are never replaced here.

Smart App Control in Enforce mode admits an unsigned binary only once it carries
cloud reputation. uv writes a per-installation trampoline into venv\Scripts, so
creating or rebuilding the venv produces a unique unsigned file with no
reputation that Windows rejects, while the shared python-build-standalone
interpreter it targets is already admitted. Upstream issues #99590 and #56554
describe this class of block.

A routine `hermes update` does not always rewrite the launcher: an observed
update that pulled 42 commits left it byte-identical. Treat regeneration as
something to detect, not to assume, which is why this repair is a no-op when
the existing launcher already runs.

This repair replaces the rejected launcher with a byte-for-byte copy of the
interpreter the venv already declares in pyvenv.cfg, so the copy inherits the
verdict Windows reached for that exact hash. sys.prefix still resolves to the
venv because pyvenv.cfg governs venv detection, not the launcher's provenance.

It never changes Application Control, adds an exclusion, installs a different
Python, or rebuilds Hermes. If the declared base interpreter is itself rejected,
there is nothing trusted to copy and the repair stops instead of guessing.
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Check,
    [string]$HermesHome
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/windows-common.ps1')
. (Join-Path $PSScriptRoot 'lib/windows-hermes.ps1')
Assert-DotfilesWindows

if ($Apply -and $Check) { throw 'Choose -Apply or -Check.' }

$hermesHome = Resolve-DotfilesHermesHome $HermesHome
if (-not $Apply -and -not $Check) {
    Write-Output ("Preview: replace a venv launcher under $hermesHome that Application Control " +
        'rejects with the interpreter declared in pyvenv.cfg, keeping the rejected file beside it.')
    return
}
if (-not (Test-Path -LiteralPath $hermesHome -PathType Container)) {
    Write-Output "Hermes is not installed at ${hermesHome}; nothing to repair."
    return
}

$checkout = Join-Path $hermesHome 'hermes-agent'
if (Test-Path -LiteralPath (Join-Path $checkout 'pm') -PathType Container) {
    # PM owns the interpreter and dependency generations. Never copy over them.
    Invoke-DotfilesHermesPython -HermesHome $HermesHome -HermesRoot $checkout -Arguments @('-c','import ssl, sqlite3; print("Hermes managed runtime imports verified.")')
    return
}

$venv = Join-Path $hermesHome 'hermes-agent/venv'
$scripts = Join-Path $venv 'Scripts'
$config = Join-Path $venv 'pyvenv.cfg'
# An unrepairable layout is not a repair failure. Report and step aside so the
# caller's own runtime probe stays the authoritative diagnostic; throwing here
# would replace "this interpreter cannot run" with a less specific message.
if (-not (Test-Path -LiteralPath $config -PathType Leaf)) {
    Write-Output "Hermes venv is incomplete (${config} is missing); nothing to repair."
    return
}
# Trust the venv's own declaration rather than searching for any interpreter:
# substituting an unrelated Python would change the runtime, not repair it.
Assert-DotfilesPreferenceFile $config
$declared = (Get-Content -LiteralPath $config | Where-Object { $_ -match '^\s*home\s*=' } |
    Select-Object -First 1) -replace '^\s*home\s*=\s*', ''
if (-not $declared) {
    Write-Output "Hermes venv declares no base interpreter in ${config}; nothing to repair."
    return
}
$declared = $declared.Trim()
if (-not (Test-Path -LiteralPath $declared -PathType Container)) {
    Write-Output "Hermes venv declares a missing base interpreter directory (${declared}); nothing to repair."
    return
}

function Test-RuntimeRuns {
    # Non-throwing counterpart to Assert-DotfilesPythonRuntime: a rejected binary
    # is the condition being measured here, not an error to abort on. The reason
    # is retained per target. Physical-file refusals must escape this probe,
    # rather than being interpreted as permission to replace the file.
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ Runs = $false; Error = 'file is missing' }
    }
    Assert-DotfilesPreferenceFile $Path
    try {
        Assert-DotfilesPythonRuntime -Path $Path -Label 'probe'
        return [pscustomobject]@{ Runs = $true; Error = '' }
    } catch {
        return [pscustomobject]@{ Runs = $false; Error = $_.Exception.GetBaseException().Message }
    }
}

# python.exe and pythonw.exe are the launchers Hermes and the updater invoke;
# console-script trampolines are not repaired because nothing here calls them.
$targets = @('python.exe', 'pythonw.exe')
$broken = @()
$missingBase = @()
$probed = 0
foreach ($name in $targets) {
    $launcher = Join-Path $scripts $name
    $source = Join-Path $declared $name
    if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) { continue }
    $probed++
    $probe = Test-RuntimeRuns $launcher
    if ($probe.Runs) { continue }
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { $missingBase += $name; continue }
    $broken += [pscustomobject]@{ Name = $name; Launcher = $launcher; Source = $source; Error = $probe.Error }
}

if ($missingBase) {
    throw ("Rejected launcher has no counterpart in the base interpreter: " +
        ($missingBase -join ', ') + ". Reinstall Hermes rather than substituting a runtime.")
}

# Nothing was probed, so nothing may be claimed about whether the venv runs.
if ($probed -eq 0) {
    Write-Output "Hermes venv has no python.exe or pythonw.exe in ${scripts}; nothing to repair."
    return
}

if (-not $broken) {
    Write-Output "Hermes venv interpreter runs; no repair needed ($scripts)."
    return
}

$names = ($broken | ForEach-Object { $_.Name }) -join ', '
# Siblings signal -Check drift by throwing; dot's Invoke-DotfilesNative accepts
# only exit 0, so a non-zero exit here would surface as a wrapper error instead.
if ($Check) {
    $reasons = ($broken | ForEach-Object { "$($_.Name): $($_.Error)" }) -join '; '
    throw "Hermes venv interpreter is rejected ($reasons). Run dot hermes-runtime -Apply."
}

# A healthy venv does not need to execute its base python.exe. Only require the
# replacement runtime once a launcher actually needs repair.
$basePython = Join-Path $declared 'python.exe'
$baseProbe = Test-RuntimeRuns $basePython
if (-not $baseProbe.Runs) {
    throw ("Hermes's declared base interpreter cannot run at ${basePython}: $($baseProbe.Error). " +
        'Nothing trusted remains to copy; resolve that before repairing the venv. ' +
        'Do not disable Application Control.')
}

# The interpreter resolves its own directory for python3xx.dll and the VC runtime,
# so a copied launcher needs them beside it; without these it exits 0xC0000135.
$runtimeLibraries = Get-ChildItem -LiteralPath $declared -Filter '*.dll' -File
# Validate the entire existing read/write set before the first copy. In
# particular, a later pythonw.exe or DLL refusal must not leave a partial repair.
$repairPaths = @($config)
foreach ($target in $broken) {
    $repairPaths += $target.Source, $target.Launcher, ($target.Launcher + '.before-dotfiles')
}
foreach ($library in $runtimeLibraries) {
    $repairPaths += $library.FullName, (Join-Path $scripts $library.Name)
}
foreach ($path in $repairPaths) {
    if (Test-Path -LiteralPath $path -PathType Leaf) { Assert-DotfilesPreferenceFile $path }
}
foreach ($library in $runtimeLibraries) {
    $destination = Join-Path $scripts $library.Name
    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $library.FullName -Algorithm SHA256).Hash) { continue }
    }
    Copy-Item -LiteralPath $library.FullName -Destination $destination -Force
    Write-Output "Placed runtime library beside the launcher: $($library.Name)"
}

foreach ($target in $broken) {
    # Keep the first rejected launcher as evidence for an upstream report, matching
    # the launcher repair's .before-dotfiles convention. A later repair overwrites
    # in place rather than replacing that original with a newer rejected copy.
    $backup = $target.Launcher + '.before-dotfiles'
    if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) {
        Copy-Item -LiteralPath $target.Launcher -Destination $backup
        Write-Output "Retained rejected launcher: $backup"
    }
    Copy-Item -LiteralPath $target.Source -Destination $target.Launcher -Force
    Write-Output "Replaced $($target.Name) with the venv's declared base interpreter."
}

foreach ($target in $broken) {
    $probe = Test-RuntimeRuns $target.Launcher
    if (-not $probe.Runs) {
        throw ("$($target.Name) is still rejected after repair at $($target.Launcher): $($probe.Error). " +
            'Application Control is denying the copied interpreter as well; report the ' +
            'blocked hash upstream instead of weakening the policy.')
    }
}
Write-Output "Hermes venv interpreter repaired and verified: $names"
