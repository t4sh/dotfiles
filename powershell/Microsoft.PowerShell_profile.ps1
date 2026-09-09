# Shared PowerShell 7 profile (Windows). Linked to
# ~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1 by
# scripts/setup-windows-tool-config.ps1. Windows PowerShell 5.1 loads the stub
# in powershell/WindowsPowerShell.Microsoft.PowerShell_profile.ps1, which
# dotsources this file.

$dotfiles = Join-Path $HOME '.dotfiles'

# Preserve exact segment order while making persistent user tools available.
. (Join-Path $dotfiles 'scripts\lib\windows-common.ps1')
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$env:Path = Merge-DotfilesPath @($userPath,$env:Path)

$zedExecutable = Join-Path $env:LOCALAPPDATA 'Programs\Zed\Zed.exe'
$env:EDITOR = if (Test-Path -LiteralPath $zedExecutable) { "$zedExecutable --wait" } elseif (Get-Command cursor -ErrorAction SilentlyContinue) { 'cursor --wait' } else { 'code --wait' }
$env:VISUAL = $env:EDITOR
$env:STARSHIP_CONFIG = Join-Path $HOME '.config\starship.toml'

if ($env:TERM -ne 'dumb' -and (Get-Command starship -ErrorAction SilentlyContinue)) {
    (& starship init powershell | Out-String) | Invoke-Expression
}
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    (& zoxide init powershell | Out-String) | Invoke-Expression
}

Set-Alias ll Get-ChildItem

function ... { Set-Location ../.. }
function .... { Set-Location ../../.. }
function ..... { Set-Location ../../../.. }
function path { $env:Path -split ';' }
function which([string]$Name) { Get-Command $Name | Select-Object -ExpandProperty Source }
function mcd([string]$Path) { New-Item -ItemType Directory -Force $Path | Out-Null; Set-Location $Path }
function free-port([int]$Port) {
    Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
        Select-Object LocalAddress, LocalPort, State, OwningProcess
}

# Load one explicitly named vault environment set into this PowerShell process.
# Nothing is imported at shell startup and nothing is persisted to the registry.
function Import-DotfilesSecretEnv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
        [string[]] $Name
    )

    $vaultRoot = Join-Path $HOME '.secrets\config\env'
    $rootPath = [IO.Path]::GetFullPath($vaultRoot).TrimEnd('\') + '\'

    foreach ($setName in $Name) {
        $envPath = [IO.Path]::GetFullPath((Join-Path $vaultRoot "$setName.env"))
        if (-not $envPath.StartsWith($rootPath, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Secret environment path escaped the vault root: $setName"
        }
        if (-not (Test-Path -LiteralPath $envPath -PathType Leaf)) {
            throw "Secret environment set not found: $setName"
        }

        $loaded = [Collections.Generic.List[string]]::new()
        foreach ($line in Get-Content -LiteralPath $envPath) {
            if ($line -match '^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
                $key = $matches[1]
                $value = $matches[2]
                if ($value.Length -ge 2 -and (
                    ($value.StartsWith('"') -and $value.EndsWith('"')) -or
                    ($value.StartsWith("'") -and $value.EndsWith("'"))
                )) {
                    $value = $value.Substring(1, $value.Length - 2)
                }
                Set-Item -LiteralPath "Env:$key" -Value $value
                $loaded.Add($key)
            }
        }

        [pscustomobject]@{
            Set       = $setName
            Variables = $loaded.ToArray()
        }
    }
}

function update-all {
    [CmdletBinding()]
    param(
        [switch] $DryRun,
        [switch] $SkipApps,
        [switch] $SkipSkills,
        [switch] $AllApps
    )

    $arguments = @('-NoProfile','-File',(Join-Path $dotfiles 'scripts\update-windows.ps1'))
    foreach ($name in $PSBoundParameters.Keys) { if ($PSBoundParameters[$name]) { $arguments += "-$name" } }
    Invoke-DotfilesNative (Resolve-DotfilesPwsh) $arguments
}
