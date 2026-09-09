#Requires -Version 7.0
[CmdletBinding()]
param([switch]$Strict, [switch]$Offline)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'lib\windows-common.ps1')
Assert-DotfilesWindows
$failed=[Collections.Generic.List[string]]::new()
function Check-Dotfiles([string]$Name,[scriptblock]$Action){
    try{& $Action | Out-Host; Write-Output "OK: $Name"}
    catch{$failed.Add($Name);Write-Warning "$Name : $($_.Exception.Message)"}
}
Check-Dotfiles 'Independent PowerShell 7.4+' { $null=Resolve-DotfilesPwsh }
Check-Dotfiles 'Persistent script policy' { Assert-DotfilesPersistentScriptPolicy }
Check-Dotfiles 'Git for Windows Bash' { $null=Resolve-DotfilesBash }
Check-Dotfiles 'Managed Python' { $null=Resolve-DotfilesPython }
Check-Dotfiles 'Stable Node shims' { foreach($name in @('node-stable','npx-stable')){ $null=Get-Command $name -ErrorAction Stop } }
Check-Dotfiles 'Package coverage' { & (Join-Path $PSScriptRoot 'check-windows-packages.ps1') -CoverageOnly }
if(-not $Offline){Check-Dotfiles 'Native package inventory' { & (Join-Path $PSScriptRoot 'check-windows-packages.ps1') -Strict | Where-Object Status -EQ 'Missing' | Format-Table Key,Package }}
Check-Dotfiles 'Configuration links' { & (Join-Path $PSScriptRoot 'setup-windows-tool-config.ps1') -Check }
Check-Dotfiles 'Windows Git overlay' {
    $helper = & git.exe config --global --includes --get credential.helper
    if ($LASTEXITCODE -ne 0 -or $helper -ne 'manager') { throw 'Windows GCM overlay is not selected.' }
    $ssh = & git.exe config --global --includes --get core.sshCommand
    if ($LASTEXITCODE -ne 0 -or $ssh -ne 'dotfiles-ssh.cmd') { throw 'Windows native OpenSSH launcher is not selected.' }
    $null=Get-Command dotfiles-ssh.cmd -ErrorAction Stop
}
Check-Dotfiles 'Tracked hooks' { & (Join-Path $PSScriptRoot 'setup-windows-hooks.ps1') -Check }
Check-Dotfiles 'Skills and rules' { & (Join-Path $PSScriptRoot 'check-windows-skills.ps1') }
Check-Dotfiles 'Impeccable engine' { & (Join-Path $PSScriptRoot 'setup-windows-skill-engine.ps1') }
Check-Dotfiles 'Editor preferences' { & (Join-Path $PSScriptRoot 'sync-windows-apps.ps1') -Mode Check }
Check-Dotfiles 'Extended app preferences' { & (Join-Path $PSScriptRoot 'sync-windows-extra-apps.ps1') -Mode Check }
foreach($editor in @('code','cursor')){Check-Dotfiles "$editor extensions" { & (Join-Path $PSScriptRoot 'install-windows-extensions.ps1') -Editor $editor -Check }}
Write-Output 'Encrypted secrets backup is an explicit separate action; recovery-key readiness and live restore are not doctor requirements. Manual vendor apps, runtime packages, font registration, account sign-in and GUI activation require their separate checks.'
if($failed.Count){Write-Warning "Doctor found $($failed.Count) incomplete check(s): $($failed -join ', ')";if($Strict){throw 'Windows doctor is not clean.'}}
