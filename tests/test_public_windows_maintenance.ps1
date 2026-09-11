#Requires -Version 7.4
# Public-owned fixtures: fake settings and refresh scripts only, no live updates.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
. (Join-Path $root 'scripts/lib/windows-common.ps1')
. (Join-Path $root 'scripts/lib/windows-links.ps1')
Assert-DotfilesWindows
$python = Resolve-DotfilesPython
$bash = Resolve-DotfilesBash
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('public-maintenance-' + [guid]::NewGuid().ToString('N'))
$encodingBefore = [Console]::OutputEncoding
$pythonEncodingBefore = $env:PYTHONIOENCODING
$pythonBinBefore = $env:PYTHON_BIN
$npxRealBefore = $env:NPX_REAL
$agentBefore = $env:DOTFILES_SKILLS_AGENT
$tempBefore = $env:TEMP
$cloudPythonBefore = $env:CLOUDSDK_PYTHON
$alias = Join-Path $fixture 'visible'
try {
    $cache = Join-Path $fixture 'Packages/fixture/LocalCache/settings'
    [IO.Directory]::CreateDirectory($cache) | Out-Null
    $source = Join-Path $fixture 'source.json'
    $physical = Join-Path $cache 'config.json'
    [IO.File]::WriteAllText($source, '{"managed":true}')
    [IO.File]::WriteAllText($physical, '{"original":true}')
    New-Item -ItemType Junction -Path $alias -Target $cache | Out-Null
    $target = Join-Path $alias 'config.json'
    foreach ($operation in @('check', 'repair')) {
        $blocked = $false
        try {
            if ($operation -eq 'check') { Get-DotfilesLinkMode $source $target | Out-Null }
            else { Set-DotfilesLink $source $target | Out-Null }
        } catch { $blocked = $_.Exception.Message -match 'redirected into an MSIX LocalCache' }
        if (-not $blocked) { throw "Hidden cache file accepted during $operation" }
        if ([IO.File]::ReadAllText($physical) -cne '{"original":true}') { throw 'Redirected file was changed' }
    }
    $ordinary = Join-Path $fixture 'ordinary.json'
    Set-DotfilesLink $source $ordinary | Out-Null
    Set-DotfilesLink $source $ordinary | Out-Null
    if ((Get-DotfilesLinkMode $source $ordinary) -notin @('HardLink', 'SymbolicLink')) { throw 'Normal link or repeat repair failed' }

    # Run the public updater's real refresh commands against dummy child scripts.
    $dotfiles = Join-Path $fixture 'refresh'
    [IO.Directory]::CreateDirectory((Join-Path $dotfiles 'scripts')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $dotfiles 'agents')) | Out-Null
    foreach ($path in @('Skillsfile', 'scripts/audit-skill-licenses.sh')) {
        [IO.File]::WriteAllText((Join-Path $dotfiles $path), "printf '\342\234\223 fixture\n'`n")
    }
    foreach ($path in @('scripts/gen-skillsfile.py', 'agents/compareskills.py')) {
        [IO.File]::WriteAllText((Join-Path $dotfiles $path), 'print(chr(0x2713) + " fixture")')
    }
    $skillsLog = Join-Path $dotfiles 'checks.log'
    $runner = Get-Content (Join-Path $root 'scripts/update-windows.ps1') -Raw
    $pattern = '(?ms)^\s*\$env:PYTHON_BIN = \$python\r?\n(?<commands>.*?)^\s*& \(Join-Path \$dotfiles ''scripts\\setup-windows-skill-engine\.ps1''\)'
    $match = [regex]::Match($runner, $pattern)
    if (-not $match.Success) { throw 'Cannot locate public refresh commands' }
    $commands = [scriptblock]::Create($match.Groups['commands'].Value)
    [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(437)
    $env:PYTHONIOENCODING = 'ascii'
    $env:PYTHON_BIN = $python
    $output = @(& $commands)
    $expected = [string][char]0x2713 + ' fixture'
    if ($output.Count -ne 2 -or $output[0] -cne 'Checking for skill updates...' -or $output[1] -cne $expected) { throw 'Public refresh progress output is incorrect' }
    $checks = @(Get-Content -LiteralPath $skillsLog)
    if ($checks.Count -ne 3 -or @($checks | Where-Object { $_ -cne $expected }).Count) { throw 'Public refresh corrupted UTF-8 checks log' }
    [IO.File]::WriteAllText($skillsLog, '')
    [IO.File]::WriteAllText((Join-Path $dotfiles 'scripts/gen-skillsfile.py'), 'import sys; sys.exit(23)')
    $failed = $false
    try { & $commands | Out-Null } catch { $failed = $_.Exception.Message -match 'exit 23' }
    if (-not $failed) { throw 'Public refresh hid a failed child process' }
    if ([Console]::OutputEncoding.CodePage -ne 437 -or $env:PYTHONIOENCODING -cne 'ascii') { throw 'Public refresh changed caller encoding' }

    # Exercise the public cmd wrapper without invoking a real installer.
    $env:TEMP = $fixture
    $env:DOTFILES_SKILLS_AGENT = 'codex'
    $env:NPX_REAL = Join-Path $fixture 'fake installer.cmd'
    $wrapper = Join-Path $root 'scripts/npx-skills-windows.cmd'
    [IO.File]::WriteAllText($env:NPX_REAL, "@echo off`r`necho installer diagnostic`r`nexit /b 0`r`n")
    $output = @(& $wrapper skills add fixture/source --skill alpha -g -y)
    if ($LASTEXITCODE -ne 0 -or $output.Count -ne 1 -or $output[0] -cne 'Checking skills from source: fixture/source') { throw 'Wrapper success output is incorrect' }
    [IO.File]::WriteAllText($env:NPX_REAL, "@echo off`r`necho installer failure diagnostic`r`nexit /b 17`r`n")
    $output = @(& $wrapper skills add fixture/source --skill alpha -g -y)
    if ($LASTEXITCODE -ne 17 -or $output.Count -ne 2 -or $output[1] -notlike '  Failed to update skills from fixture/source (exit 17); log:*') { throw 'Wrapper lost failure status or log path' }
    $installerLog = $output[1] -replace '^.*; log: ', ''
    if ((Get-Content -Raw -LiteralPath $installerLog) -notmatch 'installer failure diagnostic') { throw 'Wrapper discarded installer diagnostics' }

    # Extract the real Topgrade action; fake both native commands and their exit codes.
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($runner, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw $errors[0] }
    $command = $ast.Find({ param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Invoke-Stage' -and $node.Extent.Text -match "-Name 'Topgrade apps and developer tools'" }, $true)
    $action = ($command.CommandElements | Where-Object { $_ -is [Management.Automation.Language.ScriptBlockExpressionAst] }).ScriptBlock.GetScriptBlock()
    function Resolve-WinGetPackageCommand { return 'Invoke-FixtureTopgrade' }
    $script:copyCalls = 0
    $script:topgradeCalls = 0
    $script:topgradeExit = 0
    $script:copyExit = 0
    $script:copiedPython = Join-Path $fixture 'copied-python.exe'
    [IO.File]::WriteAllText($script:copiedPython, 'fixture only')
    function gcloud.cmd { $script:copyCalls++; $global:LASTEXITCODE = $script:copyExit; Write-Output $script:copiedPython }
    function Invoke-FixtureTopgrade { $script:topgradeCalls++; $script:observedPython = $env:CLOUDSDK_PYTHON; Write-Output 'Topgrade fixture diagnostic'; $global:LASTEXITCODE = $script:topgradeExit }
    $env:CLOUDSDK_PYTHON = 'caller-python'
    $DryRun = $false
    & $action | Out-Null
    if ($script:copyCalls -ne 1 -or $script:observedPython -cne $script:copiedPython -or $env:CLOUDSDK_PYTHON -cne 'caller-python') { throw 'Topgrade Python preparation or restoration failed' }
    $script:topgradeExit = 19
    $failed = $false
    try { & $action | Out-Null } catch { $failed = $_.Exception.Message -match 'Topgrade exited 19' }
    if (-not $failed -or $env:CLOUDSDK_PYTHON -cne 'caller-python') { throw 'Topgrade failure lost status or caller environment' }
    $script:copyExit = 21
    $callsBefore = $script:topgradeCalls
    $failed = $false
    try { & $action | Out-Null } catch { $failed = $_.Exception.Message -match 'gcloud could not prepare' }
    if (-not $failed -or $script:topgradeCalls -ne $callsBefore -or $env:CLOUDSDK_PYTHON -cne 'caller-python') { throw 'Failed Python preparation did not stop Topgrade safely' }
    $script:topgradeExit = 0
    $copiesBefore = $script:copyCalls
    $DryRun = $true
    & $action | Out-Null
    if ($script:copyCalls -ne $copiesBefore -or $script:observedPython -cne 'caller-python') { throw 'Dry run prepared or changed update Python' }

} finally {
    [Console]::OutputEncoding = $encodingBefore
    $env:PYTHONIOENCODING = $pythonEncodingBefore
    $env:PYTHON_BIN = $pythonBinBefore
    $env:NPX_REAL = $npxRealBefore
    $env:DOTFILES_SKILLS_AGENT = $agentBefore
    $env:TEMP = $tempBefore
    $env:CLOUDSDK_PYTHON = $cloudPythonBefore
    $resolved = [IO.Path]::GetFullPath($fixture)
    if ((Split-Path $resolved -Parent) -ine [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') -or (Split-Path $resolved -Leaf) -notmatch '^public-maintenance-[0-9a-f]{32}$') { throw 'Unsafe fixture cleanup path' }
    if (Test-Path -LiteralPath $alias) { [IO.Directory]::Delete($alias) }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
Write-Output 'PASS: public link redirection, repeat repair, UTF-8 refresh, compact logs, Topgrade preparation, dry run, failure status and environment restoration.'
