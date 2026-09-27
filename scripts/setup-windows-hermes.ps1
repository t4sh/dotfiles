#Requires -Version 7.4
[CmdletBinding()]
param([switch]$Apply, [switch]$Check, [switch]$SkipMissing,
    [string]$HermesHome, [string]$HermesRoot, [string]$Python)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/windows-common.ps1')
. (Join-Path $PSScriptRoot 'lib/windows-hermes.ps1')
Assert-DotfilesWindows
if ($Apply -and $Check) { throw 'Choose -Apply or -Check.' }
$HermesHome = Resolve-DotfilesHermesHome $HermesHome
$config = Join-Path $HermesHome 'config.yaml'
if (-not (Test-Path -LiteralPath $config -PathType Leaf)) {
    if ($SkipMissing) { Write-Output 'Hermes not initialized; skipped. After installation run dot hermes -Apply.'; return }
    throw "Initialize Hermes first, or select its existing home with -HermesHome. Missing: $config"
}
Assert-DotfilesPreferenceFile $config
if (-not $HermesRoot) { $HermesRoot = Join-Path $HermesHome 'hermes-agent' }
if (-not $Apply -and -not $Check) {
    Write-Output "Preview: set skills.create_dir to ~/.agents/skills and add it to skills.external_dirs in $config"
    return
}
$null = Resolve-DotfilesHermesPythonCommand -HermesRoot $HermesRoot -Python $Python
$runtimeSource = Join-Path $HermesRoot 'hermes_cli/main.py'
if (Test-Path -LiteralPath $runtimeSource -PathType Leaf) { Assert-DotfilesPreferenceFile $runtimeSource }
$helper = Join-Path $PSScriptRoot 'hermes-settings.py'
$snapshot = Join-Path (Split-Path $PSScriptRoot) 'apps/windows/hermes/config.json'
$options = @('--skills-only','--live',$config,'--snapshot',$snapshot)
# Refuse older runtimes that would accept YAML but ignore the preference.
Invoke-DotfilesHermesPython -HermesHome $HermesHome -HermesRoot $HermesRoot -Python $Python -Arguments @('-B','-c', 'import sys; from agent import skill_utils; sys.exit(0 if callable(getattr(skill_utils, "get_skill_create_dir", None)) else "Update Hermes: this runtime does not support skills.create_dir")')
if ($Apply) {
    if (-not (Test-Path -LiteralPath (Join-Path $HOME '.agents/skills') -PathType Container)) { throw 'Shared skills directory missing. Run dot link first.' }
    # Include the gateway and source Electron process, not only packaged Desktop.
    $running = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -match '^hermes(?:\.exe)?$' -or
        ($_.Name -match '^pythonw?(?:\.exe)?$' -and $_.CommandLine -match 'hermes_cli|hermes-agent|run_agent\.py') -or
        ($_.Name -ieq 'electron.exe' -and $_.ExecutablePath -and
            $_.ExecutablePath.StartsWith([IO.Path]::GetFullPath($HermesRoot).TrimEnd('\','/') + '\', [StringComparison]::OrdinalIgnoreCase))
    }
    if ($running) { throw 'Close Hermes Desktop and stop Hermes CLI/gateway sessions before applying preferences. No processes were stopped.' }
    Invoke-DotfilesHermesPython -HermesHome $HermesHome -HermesRoot $HermesRoot -Python $Python -Arguments (@('-B',$helper,'restore') + $options)
    & (Join-Path $PSScriptRoot 'setup-windows-hermes-launcher.ps1') -Apply -HermesHome $HermesHome -HermesRoot $HermesRoot -Python $Python
}
Invoke-DotfilesHermesPython -HermesHome $HermesHome -HermesRoot $HermesRoot -Python $Python -Arguments (@('-B',$helper,'check') + $options)
Invoke-DotfilesHermesPython -HermesHome $HermesHome -HermesRoot $HermesRoot -Python $Python -Arguments @('-B','-c', 'import os,sys; from pathlib import Path; os.environ["HERMES_HOME"]=sys.argv[1]; from agent.skill_utils import get_skill_create_dir; actual=get_skill_create_dir(); sys.exit(0 if actual is not None and actual.resolve()==(Path.home()/".agents/skills").resolve() else "Hermes runtime did not resolve the shared skills directory")', $HermesHome)
Invoke-DotfilesHermesPython -HermesHome $HermesHome -HermesRoot $HermesRoot -Python $Python -Arguments @('-B','-c', 'import os,sys; os.environ["HERMES_HOME"]=sys.argv[1]; from tools.skills_tool import _find_all_skills; names={s["name"] for s in _find_all_skills()}; missing={"init-rulebook","skill-architect"}-names; sys.exit("Shared skills missing from Hermes inventory: " + ", ".join(sorted(missing)) if missing else 0)', $HermesHome)
