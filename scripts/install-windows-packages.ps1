#Requires -Version 7.0
[CmdletBinding()]
param([switch]$Apply, [switch]$Upgrade, [switch]$AllInstalled,
    [string]$LogDirectory = (Join-Path $env:TEMP 'dotfiles-windows-install'), [string[]]$Only,
    [string]$AppGroups = $(if ($env:APP_GROUPS) { $env:APP_GROUPS } else { 'all' }))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\windows-common.ps1')
. (Join-Path $PSScriptRoot 'lib\windows-packages.ps1')
. (Join-Path $PSScriptRoot 'lib\windows-app-groups.ps1')
. (Join-Path $PSScriptRoot 'lib\windows-tldr.ps1')
Assert-DotfilesWindows
$rows = @(Get-DotfilesWindowsPackages)
$selection = Get-DotfilesAppGroups -Root (Split-Path $PSScriptRoot) -AppGroups $AppGroups
$packages = @(Select-DotfilesWindowsPackages -Rows $rows -Selection $selection)
if ($Only) {
    $unknown = @($Only | Where-Object { $_ -notin $packages.Id })
    if ($unknown.Count) { throw "Unknown package selection: $($unknown -join ', ')" }
    $packages = @($packages | Where-Object Id -In $Only)
}
if ($AllInstalled -and (-not $Upgrade -or $Only)) { throw '-AllInstalled requires -Upgrade and cannot be combined with -Only.' }
if (-not $Apply) {
    if ($AllInstalled) { Write-Host 'Preview: WinGet upgrade ALL installed packages (not just the manifest).' -ForegroundColor Blue }
    else { $packages | Select-Object Source,Id,Mode }
    return
}
[IO.Directory]::CreateDirectory($LogDirectory) | Out-Null
$failures = @()
$results = @()
function Get-DotfilesPackageFeedbackColor {
    param([Parameter(Mandatory)][string]$Status, [switch]$Failed)
    if ($Failed) { return [ConsoleColor]::Red }
    if ($Status -eq 'Reboot required') { return [ConsoleColor]::Yellow }
    if ($Status -in @('Already installed','Runtime update delegated to Topgrade','No applicable upgrade')) { return [ConsoleColor]::Blue }
    return [ConsoleColor]::Green
}
function Get-DotfilesDeskflowStableVersion {
    $listed=& winget.exe show --id Deskflow.Deskflow --exact --versions --source winget --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) { throw "WinGet could not list Deskflow versions (exit $LASTEXITCODE)" }
    $stable=Get-DotfilesInstallableDeskflowVersion (Get-DotfilesListedWinGetVersions $listed)
    if (-not $stable) { throw 'WinGet published no installable stable Deskflow version.' }
    return $stable
}
function Sync-DotfilesBlockedDeskflow {
    param([Parameter(Mandatory)][string]$Version, [string]$Installed, [string]$Log)
    if (-not (Test-DotfilesDeskflowRequiresReplacement $Installed $Version)) { return }
    $service=Get-Service -Name Deskflow -ErrorAction SilentlyContinue
    if ($service -and $service.Status -ne 'Stopped') { Stop-Service -Name Deskflow -Force }
    Get-Process -Name deskflow,deskflow-core,deskflow-daemon -ErrorAction SilentlyContinue | Stop-Process -Force
    $common=@('--id','Deskflow.Deskflow','--exact','--source','winget','--accept-source-agreements','--disable-interactivity')
    $uninstall=@('uninstall')+$common
    $install=@('install')+$common+@('--version',$Version,'--accept-package-agreements')
    if ($Log) {
        & winget.exe @uninstall *> $Log
        if ($LASTEXITCODE -ne 0) { throw "WinGet could not remove blocked Deskflow $Installed (exit $LASTEXITCODE); log: $Log" }
        & winget.exe @install *> $Log
        if ($LASTEXITCODE -ne 0) { throw "WinGet could not install Deskflow $Version (exit $LASTEXITCODE); log: $Log" }
    } else {
        Invoke-DotfilesNative winget.exe $uninstall
        Invoke-DotfilesNative winget.exe $install
    }
    $verified=Convert-DotfilesInstalledWinGetVersion ([string](Get-DotfilesWindowsInventory)['winget:Deskflow.Deskflow'])
    if ($verified -cne $Version) { throw "Deskflow install landed on '$verified', expected $Version" }
    $service=Get-Service -Name Deskflow -ErrorAction SilentlyContinue
    if ($service -and $service.Status -ne 'Running') { Start-Service -Name Deskflow }
    return "Replaced Smart App Control blocked Deskflow $Installed with $Version"
}
if ($AllInstalled) {
    $deskflowStable=Get-DotfilesDeskflowStableVersion
    Set-DotfilesDeskflowStablePin $deskflowStable
    Invoke-DotfilesNative winget.exe @('upgrade','--all','--accept-source-agreements','--accept-package-agreements','--disable-interactivity') @(0,-1978335189)
    $inventory=Get-DotfilesWindowsInventory
    $installed=Convert-DotfilesInstalledWinGetVersion ([string]$inventory['winget:Deskflow.Deskflow'])
    $replaced=Sync-DotfilesBlockedDeskflow -Version $deskflowStable -Installed $installed
    if ($replaced) { Write-Host "winget:Deskflow.Deskflow : $replaced" -ForegroundColor Green }
    elseif ($installed -and $installed -cne $deskflowStable -and (Test-DotfilesStableWinGetVersion $installed)) {
        Invoke-DotfilesNative winget.exe @('upgrade','--id','Deskflow.Deskflow','--exact','--source','winget','--version',$deskflowStable,'--accept-source-agreements','--accept-package-agreements','--disable-interactivity') @(0,-1978335189)
    }
    return
}
$inventory = Get-DotfilesWindowsInventory
foreach ($package in $packages) {
    $key=$package.Source+':'+$package.Id
    $log=Join-Path $LogDirectory (($key -replace '[^a-zA-Z0-9._-]','_')+'.log')
    $status='Installed'
    $packageFailed=$false
    $replaced=$null
    try {
        if ($package.Id -eq 'Deskflow.Deskflow') {
            $stable=Get-DotfilesDeskflowStableVersion
            Set-DotfilesDeskflowStablePin $stable
            $installed=Convert-DotfilesInstalledWinGetVersion ([string]$inventory[$key])
            $replaced=Sync-DotfilesBlockedDeskflow -Version $stable -Installed $installed -Log $log
            if ($replaced) { $status=$replaced }
        }
        if ($replaced) {
            # Sync-DotfilesBlockedDeskflow verified the replacement.
        } elseif ($package.Mode -eq 'runtime') {
            # Runtime upgrades are owned by Topgrade. Bootstrap installs exact manifest names.
            if ($Upgrade) { $status='Runtime update delegated to Topgrade' }
            elseif ($package.Source -eq 'uv' -and $package.Id -eq 'tldr') { Install-DotfilesTldr }
            elseif ($package.Source -eq 'uv') { Invoke-DotfilesNative uv.exe @('tool','install',$package.Id) }
            else { Invoke-DotfilesNative volta.exe @('install',$package.Id) }
        } elseif ($inventory.ContainsKey($key) -and -not $Upgrade) { $status='Already installed' }
        elseif (-not $inventory.ContainsKey($key) -and $Upgrade) { $status='Missing; run dot packages to install'; $failures += $key; $packageFailed=$true }
        else {
            $arguments = @($(if ($Upgrade) {'upgrade'} else {'install'}),'--id',$package.Id,'--exact','--source',$package.Source,'--accept-source-agreements','--accept-package-agreements','--disable-interactivity')
            if ($package.Id -eq 'Deskflow.Deskflow') {
                if ($Upgrade -and $installed -ceq $stable) { $status='No applicable upgrade' }
                else { $arguments += @('--version',$stable) }
            }
            if (-not $Upgrade) { $arguments += '--no-upgrade' }
            if ($package.Id -eq 'Microsoft.PowerShell') { $arguments += @('--scope','machine','--installer-type','wix') }
            if (-not $replaced -and $status -ne 'No applicable upgrade') {
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
        }
    } catch { $status=$_.Exception.Message; $failures += $key; $packageFailed=$true }
    $results += [pscustomobject]@{Package=$key;Status=$status;Log=$log}
    $statusColor = Get-DotfilesPackageFeedbackColor -Status $status -Failed:$packageFailed
    Write-Host "$key : $status" -ForegroundColor $statusColor
}
$results | Export-Csv -LiteralPath (Join-Path $LogDirectory 'results.csv') -NoTypeInformation -Encoding utf8
if ($failures.Count) { throw "Package stage incomplete: $($failures -join ', '). Review results.csv." }
$global:LASTEXITCODE = 0 # All per-package results have been checked above.
