# The installation launcher owns modern Hermes's interpreter and dependencies.
function Resolve-DotfilesHermesPythonCommand {
    param([Parameter(Mandatory)][string]$HermesRoot, [string]$Python)
    if ($Python) {
        Assert-DotfilesPreferenceFile $Python
        return @{File=$Python}
    }
    if (Test-Path -LiteralPath (Join-Path $HermesRoot 'pm') -PathType Container) {
        Assert-DotfilesPreferenceFile (Join-Path $HermesRoot 'hermes_bootstrap.py')
        foreach ($name in @('hermes.cmd','hermes.exe')) {
            $launcher = Join-Path $HermesRoot ".hermes/bin/$name"
            if (Test-Path -LiteralPath $launcher -PathType Leaf) {
                Assert-DotfilesPreferenceFile $launcher
                return @{File=$launcher; Managed=$true}
            }
        }
        throw 'Hermes installation launcher is missing; repair the official installation before continuing.'
    }
    $legacy = Join-Path $HermesRoot 'venv/Scripts/python.exe'
    if (-not (Test-Path -LiteralPath $legacy -PathType Leaf)) { throw 'Hermes Python runtime missing; repair Hermes or supply -Python.' }
    Assert-DotfilesPreferenceFile $legacy
    return @{File=$legacy}
}

function Invoke-DotfilesHermesPython {
    param([Parameter(Mandatory)][string]$HermesRoot, [string]$HermesHome, [string]$Python, [string[]]$Arguments)
    $command = Resolve-DotfilesHermesPythonCommand -HermesRoot $HermesRoot -Python $Python
    $previousHome = $env:HERMES_HOME
    $previousPath = $env:PATH
    try {
        if ($HermesHome) { $env:HERMES_HOME = $HermesHome }
        if ($command.Managed) {
            # Ask the published launcher for its interpreter; never select a
            # dependency-generation path or guess a Python version ourselves.
            $runtime = (Invoke-DotfilesNativeUtf8 $command.File @('--print-runtime-command')) | ConvertFrom-Json
            if ($runtime.Count -lt 4 -or -not (Test-Path -LiteralPath $runtime[0] -PathType Leaf)) { throw 'Invalid Hermes runtime command.' }
            Assert-DotfilesPreferenceFile $runtime[0]
            # cmd.exe drops PATH above 8191 characters. pnpm adds more directories
            # for nested lifecycle scripts, so start with only the host commands
            # bootstrap needs; Hermes's PM adds its own pinned tools to children.
            $hostDirectories = @(
                (Split-Path $runtime[0]), (Join-Path $HermesRoot '.hermes/bin'),
                (Split-Path (Get-Command git -ErrorAction Stop).Source),
                (Split-Path (Resolve-DotfilesPwsh)),
                [Environment]::SystemDirectory, $env:SystemRoot,
                (Join-Path $env:SystemRoot 'System32/OpenSSH'),
                (Join-Path $env:SystemRoot 'System32/Wbem'),
                (Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0')
            ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Select-Object -Unique
            $env:PATH = $hostDirectories -join [IO.Path]::PathSeparator
            $adapter = Join-Path (Split-Path $PSScriptRoot -Parent) 'hermes-python.py'
            Invoke-DotfilesNativeUtf8 $runtime[0] (@('-I',$adapter,$HermesRoot) + $Arguments)
        } else {
            Invoke-DotfilesNativeUtf8 $command.File $Arguments
        }
    } finally {
        $env:HERMES_HOME = $previousHome
        $env:PATH = $previousPath
    }
}
