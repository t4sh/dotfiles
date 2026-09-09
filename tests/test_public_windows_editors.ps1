#Requires -Version 7.4
# Public-owned fixture: all preferences and package resources are disposable.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('public-editors-'+[guid]::NewGuid().ToString('N'))
$roaming=Join-Path $fixture Roaming
$user=Join-Path $roaming 'Sublime Text/Packages/User'
$bundled=Join-Path $fixture Bundled
$recovery=Join-Path $fixture Recovery
function Assert($Condition,[string]$Message){if(-not $Condition){throw $Message}}
New-Item -ItemType Directory $user,$bundled -Force|Out-Null
# Unpacked dummy resources are enough to exercise the shared resource checker.
foreach($name in @('Package Control','Markdown')){
    New-Item -ItemType Directory (Join-Path $roaming "Sublime Text/Packages/$name") -Force|Out-Null
}
$syntax=Join-Path $roaming 'Sublime Text/Packages/Markdown/MultiMarkdown.sublime-syntax'
[IO.File]::WriteAllText($syntax,'dummy syntax resource')
$prefs=Join-Path $user Preferences.sublime-settings
[IO.File]::WriteAllText($prefs,'{"dummy.unrelated":true}')
$options=@{Only='sublime';RoamingRoot=$roaming;BackupRoot=$recovery;SublimeBundledDir=$bundled}
# Simulate closed/running editors; never terminate a real app.
$env:DOTFILES_PUBLIC_TEST_EDITOR_RUNNING=''
function Get-Process {param($Name) if($env:DOTFILES_PUBLIC_TEST_EDITOR_RUNNING){[pscustomobject]@{Name=$Name}}}
& (Join-Path $root scripts/restore-apps-windows.ps1) @options -Apply
Assert ((Get-Content $prefs -Raw|ConvertFrom-Json).'dummy.unrelated') 'Unrelated setting lost'
$before=(Get-FileHash $prefs).Hash
$env:DOTFILES_PUBLIC_TEST_EDITOR_RUNNING='1'
& (Join-Path $root scripts/restore-apps-windows.ps1) @options -Apply
& (Join-Path $root scripts/restore-apps-windows.ps1) @options -Check
# Bundled Markdown must also satisfy readiness (no third-party package required).
$markdown=Join-Path $roaming 'Sublime Text/Packages/Markdown'
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($markdown,(Join-Path $bundled Markdown.sublime-package))
Move-Item -LiteralPath $markdown -Destination (Join-Path $fixture saved-markdown)
& (Join-Path $root scripts/restore-apps-windows.ps1) @options -Check
Assert ((Get-FileHash $prefs).Hash -eq $before) 'Running no-op restore wrote preferences'
# Missing syntax must fail even though public preference Check intentionally skips drift.
Move-Item -LiteralPath (Join-Path $bundled Markdown.sublime-package) -Destination (Join-Path $fixture Markdown.saved)
$failed=$false
try{& (Join-Path $root scripts/restore-apps-windows.ps1) @options -Check}catch{$failed=$_.Exception.Message -like '*Sublime resources*'}
Assert $failed 'Missing syntax was not rejected'
Move-Item -LiteralPath (Join-Path $fixture Markdown.saved) -Destination (Join-Path $bundled Markdown.sublime-package)
# A required helper replacement must defer while running, but other stages run.
$helper=Join-Path $user default_syntax.py
Move-Item -LiteralPath $helper -Destination ($helper+'.saved')
[IO.File]::WriteAllText($helper,'dummy stale helper')
$failed=$false
$output=@(try{& (Join-Path $root scripts/restore-apps-windows.ps1) @options -Check 3>&1}catch{$failed=$_.Exception.Message -like '*Sublime helper*' -and $_.Exception.Message -like '*Sublime resources*'})
Assert $failed 'Restore did not aggregate helper and resource failures'
Assert (($output -join "`n") -like '*Public templates retained*') 'Other preference stages did not run after helper failure'
$failed=$false
try{& (Join-Path $root scripts/restore-apps-windows.ps1) @options -Apply}catch{$failed=$_.Exception.Message -like '*Close Sublime*'}
Assert $failed 'Running helper replacement was not deferred'
Assert ([IO.File]::ReadAllText($helper) -eq 'dummy stale helper') 'Running helper was overwritten'
$env:DOTFILES_PUBLIC_TEST_EDITOR_RUNNING=''
& (Join-Path $root scripts/restore-apps-windows.ps1) @options -Apply
& (Join-Path $root scripts/restore-apps-windows.ps1) @options -Check
# A targeted restore must preserve the other editor's dummy settings.
$code=Join-Path $roaming Code/User/settings.json
$cursor=Join-Path $roaming Cursor/User/settings.json
foreach($path in @($code,$cursor)){New-Item -ItemType Directory (Split-Path $path) -Force|Out-Null;[IO.File]::WriteAllText($path,'{"editor.fontSize":99}')}
$cursorBefore=(Get-FileHash $cursor).Hash
& (Join-Path $root scripts/sync-windows-apps.ps1) -Mode Restore -Only vscode -Apply -RoamingRoot $roaming -BackupRoot $recovery
Assert ((Get-FileHash $cursor).Hash -eq $cursorBefore) 'Targeted VS Code restore changed Cursor'
# Reject partial isolation before an editor CLI can be invoked.
$failed=$false
try{& (Join-Path $root scripts/install-windows-extensions.ps1) -UserDataDir $roaming -Apply}catch{$failed=$_.Exception.Message -like '*requires both*'}
Assert $failed 'Partial extension isolation was accepted'
# Execute the doctor's actual Sublime check block against this disposable profile.
# This proves dispatch, not the unrelated whole-machine doctor requirements.
$tokens=$null;$parseErrors=$null
$doctor=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root scripts/doctor-windows.ps1),[ref]$tokens,[ref]$parseErrors)
$checks=@($doctor.FindAll({param($node)
    $node -is [Management.Automation.Language.CommandAst] -and
    $node.GetCommandName() -eq 'Check-Dotfiles' -and
    $node.CommandElements[1].Value -eq 'Sublime readiness'
},$true))
Assert ($checks.Count -eq 1) 'Doctor must have exactly one Sublime readiness check'
$check=$checks[0].CommandElements[-1].ScriptBlock.GetScriptBlock()
$savedAppData=$env:APPDATA
$savedPythonDir=$env:UV_PYTHON_INSTALL_DIR
$python=@(& uv.exe python find --managed-python)
Assert ($LASTEXITCODE -eq 0 -and $python.Count -eq 1) 'Managed test interpreter missing'
$control=Join-Path $roaming 'Sublime Text/Packages/Package Control'
try {
    # Redirect preferences while retaining the existing read-only runtime cache.
    $env:UV_PYTHON_INSTALL_DIR=Split-Path (Split-Path $python[0])
    $env:APPDATA=$roaming
    & $check
    Move-Item -LiteralPath $control -Destination (Join-Path $fixture saved-control)
    $failed=$false
    try{& $check}catch{$failed=$_.Exception.Message -like '*Sublime resources*'}
    Assert $failed 'Doctor bypassed missing Sublime dependencies'
} finally {
    $env:APPDATA=$savedAppData
    $env:UV_PYTHON_INSTALL_DIR=$savedPythonDir
    if(Test-Path (Join-Path $fixture saved-control)){Move-Item -LiteralPath (Join-Path $fixture saved-control) -Destination $control}
}
Write-Output 'PASS: public editor restore, running no-op, dependency rejection, failure aggregation, targeted restore.'
Write-Output "Disposable evidence retained: $fixture"
