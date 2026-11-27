# Runs the real stage and Topgrade action with a harmless command fixture.
#Requires -Version 7.4
param([string]$Repository = (Split-Path $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $Repository 'scripts/update-windows.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw $parseErrors[0] }
if ($ast.Extent.Text -match 'update-windows-hermes\.ps1') { throw 'Automatic maintenance still invokes the blocked Hermes updater' }
$topgradeConfig = Get-Content (Join-Path $Repository 'config/topgrade-windows.toml') -Raw
if ($topgradeConfig -notmatch '(?s)disable\s*=\s*\[[^\]]*"opencode"') { throw 'Topgrade must leave the WinGet-managed OpenCode CLI to the package stage' }
$opencodePackage = @(Import-Csv (Join-Path $Repository 'config/windows-packages.tsv') -Delimiter "`t" | Where-Object Key -EQ 'brew:opencode')
if ($opencodePackage.Count -ne 1 -or $opencodePackage[0].Mode -ne 'native' -or $opencodePackage[0].Source -ne 'winget' -or $opencodePackage[0].Id -ne 'Anomaly.OpenCode') { throw 'OpenCode updates require the native Anomaly.OpenCode WinGet mapping' }
if ($topgradeConfig -notmatch '(?s)disable\s*=\s*\[[^\]]*"hermes_agent"') { throw 'Topgrade would reintroduce automatic Hermes updates' }
foreach ($name in @('WinGet applications','Topgrade apps and developer tools','TLDR pages','Repo-managed agent skills','Windows command paths')) {
    if (!$ast.Extent.Text.Contains("-Name '$name'")) { throw "Non-Hermes maintenance stage missing: $name" }
}
$lineColor = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-DotfilesUpdateOutputColor' }, $true)
if (-not $lineColor) { throw 'Topgrade output color policy missing' }
Invoke-Expression $lineColor.Extent.Text
$streamOutput = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Write-DotfilesUpdateOutput' }, $true)
if (-not $streamOutput) { throw 'Update output stream renderer missing' }
Invoke-Expression $streamOutput.Extent.Text
if ((Get-DotfilesUpdateOutputColor -Text 'Beginning update. This process may take several minutes.') -ne [ConsoleColor]::Blue) { throw 'Informational progress is not blue' }
if ((Get-DotfilesUpdateOutputColor -Text 'info: Checking for updates...') -ne [ConsoleColor]::Blue) { throw 'Info stream is not blue' }
if ((Get-DotfilesUpdateOutputColor -Text 'success: You are already on the latest version') -ne [ConsoleColor]::Green) { throw 'Success stream is not green' }
if ((Get-DotfilesUpdateOutputColor -Text 'All components are up to date') -ne [ConsoleColor]::Green) { throw 'Up-to-date status is not green' }
if ((Get-DotfilesUpdateOutputColor -Text 'Extension ''anthropic.claude-code'' was successfully updated.') -ne [ConsoleColor]::Green) { throw 'Updated extension status is not green' }
if ((Get-DotfilesUpdateOutputColor -Text 'changed 11 packages in 9s') -ne [ConsoleColor]::Green) { throw 'Updated package status is not green' }
if ((Get-DotfilesUpdateOutputColor -Text 'Nothing to upgrade') -ne [ConsoleColor]::Blue) { throw 'No-op update status is not blue' }
if ((Get-DotfilesUpdateOutputColor -Text '') -ne [ConsoleColor]::Blue) { throw 'Blank progress line is not handled' }
if ((Get-DotfilesUpdateOutputColor -Text 'Project mirrors synced under C:\\fixture\\Projects') -ne [ConsoleColor]::Green) { throw 'Project sync success is not green' }
if ((Get-DotfilesUpdateOutputColor -Text '[DEP0169] DeprecationWarning: url.parse()' ) -ne [ConsoleColor]::Yellow) { throw 'Deprecation warning is not yellow' }
if ((Get-DotfilesUpdateOutputColor -Text '(Use --trace-deprecation to show the warning)' -WarningContinuation) -ne [ConsoleColor]::Yellow) { throw 'Warning continuation is not yellow' }
if ((Get-DotfilesUpdateOutputColor -Text 'npm error failed to update') -ne [ConsoleColor]::Red) { throw 'Error output is not red' }
if ((Get-DotfilesUpdateOutputColor -Text "`e[31mAll components are up to date`e[0m") -ne [ConsoleColor]::Green) { throw 'Embedded ANSI color was not normalized before classification' }
$packageAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $Repository 'scripts/install-windows-packages.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw $parseErrors[0] }
$packageColor = $packageAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-DotfilesPackageFeedbackColor' }, $true)
if (-not $packageColor) { throw 'Package feedback color policy missing' }
Invoke-Expression $packageColor.Extent.Text
if ((Get-DotfilesPackageFeedbackColor -Status 'Installed') -ne [ConsoleColor]::Green) { throw 'Successful package status is not green' }
if ((Get-DotfilesPackageFeedbackColor -Status 'Already installed') -ne [ConsoleColor]::Blue) { throw 'Informational package status is not blue' }
if ((Get-DotfilesPackageFeedbackColor -Status 'Reboot required') -ne [ConsoleColor]::Yellow) { throw 'Reboot-required status is not yellow' }
if ((Get-DotfilesPackageFeedbackColor -Status 'WinGet failed' -Failed) -ne [ConsoleColor]::Red) { throw 'Failed package status is not red' }
$tldrAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $Repository 'scripts/lib/windows-tldr.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw $parseErrors[0] }
$tldrColor = $tldrAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-DotfilesTldrFeedbackColor' }, $true)
if (-not $tldrColor) { throw 'TLDR feedback color policy missing' }
Invoke-Expression $tldrColor.Extent.Text
if ((Get-DotfilesTldrFeedbackColor -Text 'Updated cache for language en: 4 entries') -ne [ConsoleColor]::Green) { throw 'TLDR success is not green' }
if ((Get-DotfilesTldrFeedbackColor -Text 'Error: language update failed') -ne [ConsoleColor]::Red) { throw 'TLDR error is not red' }
if ((Get-DotfilesTldrFeedbackColor -Text 'Warning: some cache entries are stale') -ne [ConsoleColor]::Yellow) { throw 'TLDR warning is not yellow' }
$stage = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-Stage' }, $true)
Invoke-Expression $stage.Extent.Text
$command = $ast.Find({ param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Invoke-Stage' -and $node.Extent.Text -match "-Name 'Topgrade apps and developer tools'" }, $true)
$action = ($command.CommandElements | Where-Object { $_ -is [Management.Automation.Language.ScriptBlockExpressionAst] }).ScriptBlock.GetScriptBlock()
function Assert-FeedbackColor {
    param([object[]]$Records, [string]$Text, [ConsoleColor]$Expected)
    $record = $Records | Where-Object {
        $_ -is [Management.Automation.InformationRecord] -and
        $_.MessageData -is [System.Management.Automation.HostInformationMessage] -and
        $_.MessageData.Message.Contains($Text, [StringComparison]::Ordinal)
    } | Select-Object -First 1
    if (-not $record) {
        $captured = @($Records | Where-Object { $_ -is [Management.Automation.InformationRecord] -and $_.MessageData -is [System.Management.Automation.HostInformationMessage] } | ForEach-Object { "'$($_.MessageData.Message)' [$($_.MessageData.ForegroundColor)]" }) -join '; '
        throw "Missing host feedback: $Text; captured: $captured"
    }
    if ($record.MessageData.ForegroundColor -ne $Expected) { throw "$Text expected $Expected, got $($record.MessageData.ForegroundColor)" }
}
$warningOutput = @(Write-Warning 'fixture warning' -WarningAction Continue 3>&1 | Write-DotfilesUpdateOutput 6>&1)
Assert-FeedbackColor $warningOutput 'fixture warning' Yellow
$nativeProbe = '[Console]::Error.WriteLine("[DEP0169] DeprecationWarning: fixture warning"); [Console]::Error.WriteLine("(Use --trace-deprecation to show the warning)"); [Console]::Error.WriteLine("info: Checking for updates..."); [Console]::Error.WriteLine("All components are up to date"); [Console]::Error.WriteLine("error: native fixture failed")'
$nativeOutput = @(& (Join-Path $PSHOME 'pwsh.exe') -NoProfile -Command $nativeProbe 2>&1 | Write-DotfilesUpdateOutput 6>&1)
Assert-FeedbackColor $nativeOutput '[DEP0169] DeprecationWarning' Yellow
Assert-FeedbackColor $nativeOutput '(Use --trace-deprecation' Yellow
Assert-FeedbackColor $nativeOutput 'info: Checking for updates...' Blue
Assert-FeedbackColor $nativeOutput 'All components are up to date' Green
Assert-FeedbackColor $nativeOutput 'error: native fixture failed' Red
function Resolve-WinGetPackageCommand { return 'Invoke-FixtureTopgrade' }
$originalEncoding = [Console]::OutputEncoding
$originalNoColor = $env:NO_COLOR
[Console]::OutputEncoding = [Text.Encoding]::GetEncoding(437)
function Invoke-FixtureTopgrade {
    if ([Console]::OutputEncoding.CodePage -ne 65001) { throw 'Topgrade output is not decoded as UTF-8' }
    if ($env:NO_COLOR -ne '1') { throw 'Topgrade child output did not disable embedded colors' }
    Write-Error '[DEP0169] DeprecationWarning: url.parse() is not standardized' -ErrorAction Continue
    Write-Error '(Use --trace-deprecation to show the warning)' -ErrorAction Continue
    Write-Error 'info: Checking for updates...' -ErrorAction Continue
    Write-Error 'Codex: FAILED (fixture)' -ErrorAction Continue
    $global:LASTEXITCODE = 17
}
$dotfiles = $Repository
$DryRun = $true
$failed = [Collections.Generic.List[string]]::new()
$winGetCommand = $ast.Find({ param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Invoke-Stage' -and $node.Extent.Text -match "-Name 'WinGet applications'" }, $true)
$winGetAction = ($winGetCommand.CommandElements | Where-Object { $_ -is [Management.Automation.Language.ScriptBlockExpressionAst] }).ScriptBlock.GetScriptBlock()
$previewOutput = @(Invoke-Stage -Name 'WinGet preview fixture' -Action $winGetAction 6>&1 3>&1)
Assert-FeedbackColor $previewOutput '-> WinGet preview fixture' Blue
Assert-FeedbackColor $previewOutput 'Source' Blue
Assert-FeedbackColor $previewOutput '<- WinGet preview fixture' Green
if ($failed.Count) { throw 'Safe WinGet preview reported failure' }
$output = @(Invoke-Stage -Name 'Topgrade fixture' -Action $action 6>&1 3>&1)
Assert-FeedbackColor $output '-> Topgrade fixture' Blue
Assert-FeedbackColor $output 'Topgrade fixture failed:' Red
Assert-FeedbackColor $output '<- Topgrade fixture' Red
Assert-FeedbackColor $output 'Topgrade log:' Blue
Assert-FeedbackColor $output '[DEP0169] DeprecationWarning' Yellow
Assert-FeedbackColor $output '(Use --trace-deprecation' Yellow
Assert-FeedbackColor $output 'info: Checking for updates...' Blue
Assert-FeedbackColor $output 'Codex: FAILED' Red
if ($failed.Count -ne 1 -or $failed[0] -notmatch 'Topgrade exited 17') { throw 'Topgrade exit status lost' }
if ($env:NO_COLOR -cne $originalNoColor) { throw 'Topgrade failure did not restore NO_COLOR' }
if ([Console]::OutputEncoding.CodePage -ne 437) { throw 'Topgrade failure changed caller encoding' }
if ($failed[0] -match 'UAC|microsoft_store') { throw 'Unrelated Store advice returned' }
$logLine = $output | ForEach-Object { [string]$_ } | Where-Object { $_ -like 'Topgrade log: *' }
$logPath = $logLine -replace '^Topgrade log: ', ''
if (-not $logPath -or (Get-Content -Raw -LiteralPath $logPath) -notmatch 'Codex: FAILED') { throw 'Underlying failure log missing' }
if (-not ($output | Where-Object { [string]$_ -match '<- Topgrade fixture \(' })) { throw 'Stage duration missing' }
function Invoke-FixtureTopgrade {
    if ($env:NO_COLOR -ne '1') { throw 'Topgrade child output did not disable embedded colors' }
    Write-Output "`e[31mAll components are up to date`e[0m"
    $global:LASTEXITCODE = 0
}
$failed.Clear()
$successOutput = @(Invoke-Stage -Name 'Topgrade success fixture' -Action $action 6>&1 3>&1)
Assert-FeedbackColor $successOutput '-> Topgrade success fixture' Blue
Assert-FeedbackColor $successOutput '<- Topgrade success fixture' Green
Assert-FeedbackColor $successOutput 'All components are up to date' Green
if ($failed.Count) { throw 'Successful Topgrade reported failure' }
if ([Console]::OutputEncoding.CodePage -ne 437) { throw 'Topgrade success changed caller encoding' }
if ($env:NO_COLOR -cne $originalNoColor) { throw 'Topgrade success did not restore NO_COLOR' }
[Console]::OutputEncoding = $originalEncoding
Write-Output 'PASS: actual updater action preserves failure logs, exit status, duration, and success.'
