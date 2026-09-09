# Windows PowerShell 5.1 stub. Linked to
# ~/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1.
# Prefer the repo profile; fall back to the PowerShell 7 Documents path.
$candidates = @(
    (Join-Path $HOME '.dotfiles\powershell\Microsoft.PowerShell_profile.ps1'),
    (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShell\Microsoft.PowerShell_profile.ps1')
)
foreach ($sharedProfile in $candidates) {
    if (Test-Path -LiteralPath $sharedProfile -PathType Leaf) {
        . $sharedProfile
        break
    }
}
