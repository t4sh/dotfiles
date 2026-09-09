#Requires -Version 7.0
[CmdletBinding()]
param([switch]$Apply)
Write-Output 'Public snapshots do not capture Raycast extension inventories. Export settings manually into ~/.secrets/apps/raycast/ before encrypted backup.'
