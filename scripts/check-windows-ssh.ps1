# Read-only readiness check. No key generation, registration or ACL mutation.
#Requires -Version 7.0
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\windows-common.ps1')
Assert-DotfilesWindows
$ssh = Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'
if (-not (Test-Path -LiteralPath $ssh)) { throw 'Windows OpenSSH Client is missing. Install it in Optional Features.' }
foreach ($relative in @('.ssh\config','.ssh\known_hosts','.ssh\allowed_signers','.secrets\ssh\github_ed25519')) {
    if (-not (Test-Path -LiteralPath (Join-Path $HOME $relative) -PathType Leaf)) { throw "Missing SSH prerequisite: $relative. Existing secrets are preserved; recovery is deferred." }
}
$key = Join-Path $HOME '.secrets\ssh\github_ed25519'
$acl = Get-Acl -LiteralPath $key
$broad = @('S-1-1-0','S-1-5-11','S-1-5-32-545')
foreach ($rule in $acl.Access) {
    $sid = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
    if ($sid -in $broad -and $rule.AccessControlType -eq 'Allow') { throw 'SSH key has broad access permissions; review its ACL locally before use.' }
}
Write-Output 'SSH files and basic ACL checks passed. Agent loading, server authentication and signing remain separate operator checks.'
