#Requires -Version 7.4
# Resolution only. This does not read or write the live association registry.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot) 'scripts/check-windows-vlc-associations.ps1')

function Assert-VlcChoice([string]$Actual, [string]$Expected, [string]$Name) {
    if ($Actual -cne $Expected) { throw "$Name resolved to '$Actual', expected '$Expected'." }
}

$mediaPlayer = 'AppXqj98qxeaynz6dv4459ayz6bnqxbyaqcs'
Assert-VlcChoice (Resolve-DotfilesVlcProgId -LatestProgId 'VLC.mp4.Document' -LegacyProgId $mediaPlayer -RegisteredProgId 'VLC.mp4.Document' -HashVersion 1) 'VLC.mp4.Document' 'HashVersion 1'
Assert-VlcChoice (Resolve-DotfilesVlcProgId -LatestProgId 'VLC.mp4.Document' -LegacyProgId $mediaPlayer -RegisteredProgId 'VLC.mp4.Document' -HashVersion 0) $mediaPlayer 'HashVersion 0'
Assert-VlcChoice (Resolve-DotfilesVlcProgId -LatestProgId '' -LegacyProgId '' -RegisteredProgId 'VLC.aif.Document' -HashVersion 1) 'VLC.aif.Document' 'registered fallback'
Assert-VlcChoice (Resolve-DotfilesVlcProgId -LatestProgId 'VLC.flv.Document' -LegacyProgId '' -RegisteredProgId '' -HashVersion 0) 'VLC.flv.Document' 'latest without legacy'
Write-Output 'PASS: VLC association resolution prefers the active Windows choice'
