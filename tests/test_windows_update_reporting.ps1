# Runs the real stage and Topgrade action with a harmless command fixture.
#Requires -Version 7.4
param([string]$Repository = (Split-Path $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $Repository 'scripts/update-windows.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw $parseErrors[0] }
if ($ast.Extent.Text -match 'update-windows-hermes\.ps1') { throw 'Automatic maintenance still invokes the blocked Hermes updater' }
$topgradeConfig = Get-Content (Join-Path $Repository 'config/topgrade-windows.toml') -Raw
if ($topgradeConfig -notmatch '(?s)disable\s*=\s*\[[^\]]*"hermes_agent"') { throw 'Topgrade would reintroduce automatic Hermes updates' }
foreach ($name in @('WinGet applications','Topgrade apps and developer tools','TLDR pages','Repo-managed agent skills','Windows command paths')) {
    if (!$ast.Extent.Text.Contains("-Name '$name'")) { throw "Non-Hermes maintenance stage missing: $name" }
}
$stage = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-Stage' }, $true)
Invoke-Expression $stage.Extent.Text
$command = $ast.Find({ param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Invoke-Stage' -and $node.Extent.Text -match "-Name 'Topgrade apps and developer tools'" }, $true)
$action = ($command.CommandElements | Where-Object { $_ -is [Management.Automation.Language.ScriptBlockExpressionAst] }).ScriptBlock.GetScriptBlock()
function Resolve-WinGetPackageCommand { return 'Invoke-FixtureTopgrade' }
$originalEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = [Text.Encoding]::GetEncoding(437)
function Invoke-FixtureTopgrade {
    if ([Console]::OutputEncoding.CodePage -ne 65001) { throw 'Topgrade output is not decoded as UTF-8' }
    Write-Output 'Codex: FAILED (fixture)'; $global:LASTEXITCODE = 17
}
$dotfiles = $Repository
$DryRun = $true
$failed = [Collections.Generic.List[string]]::new()
$output = @(Invoke-Stage -Name 'Topgrade fixture' -Action $action 6>&1 3>&1)
if ($failed.Count -ne 1 -or $failed[0] -notmatch 'Topgrade exited 17') { throw 'Topgrade exit status lost' }
if ([Console]::OutputEncoding.CodePage -ne 437) { throw 'Topgrade failure changed caller encoding' }
if ($failed[0] -match 'UAC|microsoft_store') { throw 'Unrelated Store advice returned' }
$logLine = $output | ForEach-Object { [string]$_ } | Where-Object { $_ -like 'Topgrade log: *' }
$logPath = $logLine -replace '^Topgrade log: ', ''
if (-not $logPath -or (Get-Content -Raw -LiteralPath $logPath) -notmatch 'Codex: FAILED') { throw 'Underlying failure log missing' }
if (-not ($output | Where-Object { [string]$_ -match '<- Topgrade fixture \(' })) { throw 'Stage duration missing' }
function Invoke-FixtureTopgrade { Write-Output 'Fixture: OK'; $global:LASTEXITCODE = 0 }
$failed.Clear()
Invoke-Stage -Name 'Topgrade success fixture' -Action $action
if ($failed.Count) { throw 'Successful Topgrade reported failure' }
if ([Console]::OutputEncoding.CodePage -ne 437) { throw 'Topgrade success changed caller encoding' }
[Console]::OutputEncoding = $originalEncoding
Write-Output 'PASS: actual updater action preserves failure logs, exit status, duration, and success.'
