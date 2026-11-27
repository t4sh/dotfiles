#Requires -Version 7.4
[CmdletBinding()]
param([switch]$Check, [switch]$OpenSettings,
    [string]$Manifest=(Join-Path (Split-Path $PSScriptRoot) 'config/windows-vlc-associations.tsv'))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'lib/windows-common.ps1')

function Resolve-DotfilesVlcProgId {
    param([string]$LatestProgId,[string]$LegacyProgId,[string]$RegisteredProgId,[int]$HashVersion)
    # Windows 11 HashVersion 1 resolves UserChoiceLatest and keeps the previous UserChoice for rollback.
    if ($HashVersion -ge 1 -and $LatestProgId) { return $LatestProgId }
    if ($LegacyProgId) { return $LegacyProgId }
    if ($LatestProgId) { return $LatestProgId }
    return $RegisteredProgId
}
function Get-DotfilesAppDefaultHashVersion {
    $sid=[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $key=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SOFTWARE\Microsoft\Windows\CurrentVersion\SystemProtectedUserData\$sid\AnyoneRead\AppDefaults")
    if (-not $key) { return 0 }
    try {
        $version=$key.GetValue('HashVersion')
        if ($null -eq $version) { return 0 }
        return [int]$version
    } finally { $key.Close() }
}

if ($MyInvocation.InvocationName -ne '.') {
Assert-DotfilesWindows

if (-not (Test-Path -LiteralPath $Manifest -PathType Leaf)) { throw "VLC association manifest missing: $Manifest" }
$extensions=[Collections.Generic.List[string]]::new()
$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($line in [IO.File]::ReadAllLines($Manifest)) {
    $entry=$line.Trim()
    if (-not $entry -or $entry.StartsWith('#') -or $entry -eq 'extension') { continue }
    if ($entry -cnotmatch '^\.[a-z0-9]+$' -or -not $seen.Add($entry)) { throw "Invalid or duplicate VLC extension: $entry" }
    $extensions.Add($entry)
}
if ($extensions.Count -eq 0) { throw 'VLC association manifest is empty.' }

$capabilities=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Clients\Media\VLC\Capabilities\FileAssociations')
if (-not $capabilities) { $capabilities=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('SOFTWARE\Clients\Media\VLC\Capabilities\FileAssociations') }
$missing=[Collections.Generic.List[string]]::new()
$unsupported=[Collections.Generic.List[string]]::new()
$matched=0
$hashVersion=Get-DotfilesAppDefaultHashVersion
foreach($ext in $extensions) {
    $expected=if($capabilities){[string]$capabilities.GetValue($ext)}else{''}
    $base="Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$ext"
    $latestKey=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("$base\UserChoiceLatest\ProgId")
    $legacyKey=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("$base\UserChoice")
    $latest=if($latestKey){[string]$latestKey.GetValue('ProgId')}else{''}
    $legacy=if($legacyKey){[string]$legacyKey.GetValue('ProgId')}else{''}
    if ($latestKey) { $latestKey.Close() }
    if ($legacyKey) { $legacyKey.Close() }
    $registered=''
    $fallback=[Microsoft.Win32.Registry]::ClassesRoot.OpenSubKey($ext)
    if ($fallback) { $registered=[string]$fallback.GetValue(''); $fallback.Close() }
    $actual=Resolve-DotfilesVlcProgId -LatestProgId $latest -LegacyProgId $legacy -RegisteredProgId $registered -HashVersion $hashVersion
    if (($expected -and $actual -ieq $expected) -or $actual -ieq 'Applications\vlc.exe') { $matched++ }
    elseif (-not $expected) { $unsupported.Add("$ext (current: $(if($actual){$actual}else{'unset'}))") }
    else { $missing.Add("$ext (current: $(if($actual){$actual}else{'unset'}))") }
}
if ($capabilities) { $capabilities.Close() }

Write-Output "VLC defaults: $matched/$($extensions.Count) matched; $($missing.Count) different; $($unsupported.Count) not advertised by this VLC installation."
if ($missing.Count) { Write-Output "Set in Windows Settings: $($missing -join ', ')" }
if ($unsupported.Count) { Write-Output "Review VLC registration or leave these manual: $($unsupported -join ', ')" }
if ($OpenSettings) {
    $registered=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\RegisteredApplications')
    $uri=if($registered -and $registered.GetValue('VLC')){'ms-settings:defaultapps?registeredAppMachine=VLC'}else{'ms-settings:defaultapps'}
    if ($registered) { $registered.Close() }
    Start-Process $uri
    Write-Output 'Choose VLC for the listed extensions in Windows Settings, then run: dot default-apps -Check'
}
if ($Check -and ($missing.Count -or $unsupported.Count)) { throw 'VLC file associations have not converged.' }
}
