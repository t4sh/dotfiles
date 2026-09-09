#Requires -Version 7.0
[CmdletBinding()]
param([switch]$Apply, [switch]$Upgrade, [switch]$AllInstalled,
    [string]$LogDirectory = (Join-Path $env:TEMP 'dotfiles-windows-install'), [string[]]$Only)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\windows-common.ps1')
. (Join-Path $PSScriptRoot 'lib\windows-packages.ps1')
. (Join-Path $PSScriptRoot 'lib\windows-tldr.ps1')
Assert-DotfilesWindows
$rows = @(Get-DotfilesWindowsPackages)
$packages = @($rows | Where-Object Mode -In @('native','runtime') | Sort-Object Source,Id -Unique)
if ($Only) {
    $unknown = @($Only | Where-Object { $_ -notin $packages.Id })
    if ($unknown.Count) { throw "Unknown package selection: $($unknown -join ', ')" }
    $packages = @($packages | Where-Object Id -In $Only)
}
if ($AllInstalled -and (-not $Upgrade -or $Only)) { throw '-AllInstalled requires -Upgrade and cannot be combined with -Only.' }
if (-not $Apply) {
    if ($AllInstalled) { Write-Output 'Preview: WinGet upgrade ALL installed packages (not just the manifest).' }
    else { $packages | Select-Object Source,Id,Mode }
    return
}
[IO.Directory]::CreateDirectory($LogDirectory) | Out-Null
$failures = @()
$results = @()
if ($AllInstalled) {
    Invoke-DotfilesNative winget.exe @('upgrade','--all','--accept-source-agreements','--accept-package-agreements','--disable-interactivity') @(0,-1978335189)
    return
}
$inventory = Get-DotfilesWindowsInventory
foreach ($package in $packages) {
    $key=$package.Source+':'+$package.Id
    $log=Join-Path $LogDirectory (($key -replace '[^a-zA-Z0-9._-]','_')+'.log')
    $status='Installed'
    try {
        if ($package.Mode -eq 'runtime') {
            # Runtime upgrades are owned by Topgrade. Bootstrap installs exact manifest names.
            if ($Upgrade) { $status='Runtime update delegated to Topgrade' }
            elseif ($package.Source -eq 'uv' -and $package.Id -eq 'tldr') { Install-DotfilesTldr }
            elseif ($package.Source -eq 'uv') { Invoke-DotfilesNative uv.exe @('tool','install',$package.Id) }
            else { Invoke-DotfilesNative volta.exe @('install',$package.Id) }
        } elseif ($inventory.ContainsKey($key) -and -not $Upgrade) { $status='Already installed' }
        elseif (-not $inventory.ContainsKey($key) -and $Upgrade) { $status='Missing; run dot packages to install'; $failures += $key }
        else {
            $arguments = @($(if ($Upgrade) {'upgrade'} else {'install'}),'--id',$package.Id,'--exact','--source',$package.Source,'--accept-source-agreements','--accept-package-agreements','--disable-interactivity')
            if (-not $Upgrade) { $arguments += '--no-upgrade' }
            if ($package.Id -eq 'Microsoft.PowerShell') { $arguments += @('--scope','machine','--installer-type','wix') }
            & winget.exe @arguments *> $log
            $code = $LASTEXITCODE
            if ($Upgrade -and $code -eq -1978335189) { $status='No applicable upgrade' }
            elseif ($code -in @(1641,3010)) { $status='Reboot required'; $failures += $key }
            elseif ($code -ne 0) { throw "WinGet failed (exit $code); log: $log. If elevation is required, rerun this package explicitly in an elevated terminal." }
            else {
                $verified = Get-DotfilesWindowsInventory
                if (-not $verified.ContainsKey($key)) { throw "Installer returned success but package identity not found: $key" }
            }
        }
    } catch { $status=$_.Exception.Message; $failures += $key }
    $results += [pscustomobject]@{Package=$key;Status=$status;Log=$log}
    Write-Host "$key : $status"
}
$results | Export-Csv -LiteralPath (Join-Path $LogDirectory 'results.csv') -NoTypeInformation -Encoding utf8
if ($failures.Count) { throw "Package stage incomplete: $($failures -join ', '). Review results.csv." }
$global:LASTEXITCODE = 0 # All per-package results have been checked above.
