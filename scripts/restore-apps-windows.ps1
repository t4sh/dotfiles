#Requires -Version 7.0
[CmdletBinding()]
param([switch]$Apply, [switch]$Check,
    [ValidateSet('sublime','vscode','cursor')][string]$Only,
    [string]$RoamingRoot=$env:APPDATA,
    [string]$BackupRoot, [string]$ExtensionsDir,
    [string]$SublimeBundledDir=(Join-Path $env:ProgramFiles 'Sublime Text/Packages'))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'lib/windows-common.ps1')
. (Join-Path $PSScriptRoot 'lib/windows-links.ps1')
Assert-DotfilesWindows
if ($ExtensionsDir -and $Only -notin @('vscode','cursor')) { throw '-ExtensionsDir requires -Only vscode or -Only cursor.' }
$isolatedRoaming = [IO.Path]::GetFullPath($RoamingRoot).TrimEnd('\','/') -ine [IO.Path]::GetFullPath($env:APPDATA).TrimEnd('\','/')
if ($ExtensionsDir -and -not $isolatedRoaming) {
    throw 'An isolated editor restore requires a separate -RoamingRoot and -ExtensionsDir; no live preferences will be changed.'
}
if ($isolatedRoaming -and $Only -ne 'sublime' -and -not $ExtensionsDir) {
    throw 'An isolated editor restore requires -Only vscode or -Only cursor and -ExtensionsDir; no live extensions will be changed.'
}
$mode=if($Check){'Check'}else{'Restore'}
$options=@{Mode=$mode;Apply=$Apply;RoamingRoot=$RoamingRoot}
if ($Only) { $options.Only=$Only }
if ($BackupRoot) { $options.BackupRoot=$BackupRoot }
$failures=[Collections.Generic.List[string]]::new()
function Invoke-RestoreStep([string]$Name,[scriptblock]$Action) {
    try { & $Action } catch { $failures.Add("${Name}: $($_.Exception.Message)"); Write-Warning $failures[-1] }
}
if (-not $Only -or $Only -eq 'sublime') {
Invoke-RestoreStep 'Sublime helper' {
$helper=Join-Path (Split-Path $PSScriptRoot) 'apps/sublime-text/default_syntax.py'
$target=Join-Path $RoamingRoot 'Sublime Text/Packages/User/default_syntax.py'
if (Test-Path -LiteralPath $target -PathType Leaf) { Assert-DotfilesPreferenceFile $target }
$preferences=Join-Path $RoamingRoot 'Sublime Text/Packages/User/Preferences.sublime-settings'
if (Test-Path -LiteralPath $preferences -PathType Leaf) { Assert-DotfilesPreferenceFile $preferences }
$helperMatches=(Get-DotfilesLinkMode $helper $target) -in @('HardLink','SymbolicLink')
if ($Check) {
    if (-not $helperMatches) { throw 'Sublime default-syntax helper is missing or drifted. Run dot restore-apps -Only sublime -Apply.' }
} elseif ($Apply -and -not $helperMatches) {
    if (Get-Process sublime_text -ErrorAction SilentlyContinue) { throw 'Close Sublime Text before replacing its default-syntax helper; existing helper preserved.' }
    Set-DotfilesLink $helper $target
}
elseif (-not $Apply) { Write-Output "Preview Restore : $target" }
}
}
Invoke-RestoreStep 'Editor preferences' { & (Join-Path $PSScriptRoot 'sync-windows-apps.ps1') @options }
if ($Only -notin @('vscode','cursor')) { Invoke-RestoreStep 'Extended preferences' { & (Join-Path $PSScriptRoot 'sync-windows-extra-apps.ps1') @options } }
foreach ($editor in @('vscode','cursor')) {
    if ($Only -and $Only -ne $editor) { continue }
    $extensionOptions=@{Editor=$(if($editor -eq 'vscode'){'code'}else{'cursor'});Apply=$Apply;Check=$Check}
    if ($ExtensionsDir) {
        $extensionOptions.ExtensionsDir=$ExtensionsDir
        $extensionOptions.UserDataDir=Join-Path $RoamingRoot $(if($editor -eq 'vscode'){'Code'}else{'Cursor'})
    }
    Invoke-RestoreStep "$editor extensions" { & (Join-Path $PSScriptRoot 'install-windows-extensions.ps1') @extensionOptions }
}
if (($Apply -or $Check) -and (-not $Only -or $Only -eq 'sublime')) {
Invoke-RestoreStep 'Sublime resources' {
    $packageSettings=Join-Path $RoamingRoot 'Sublime Text/Packages/User/Package Control.sublime-settings'
    Assert-DotfilesPreferenceFile $packageSettings
    $base=Join-Path $RoamingRoot 'Sublime Text'
    # One shared definition of readiness, including bundled and unpacked packages.
    try {
        Invoke-DotfilesNative (Resolve-DotfilesPython) @((Join-Path $PSScriptRoot 'check-sublime.py'),
            '--data-dir',$base,'--bundled-dir',$SublimeBundledDir,'--repo',(Split-Path $PSScriptRoot))
    } catch {
        throw "Sublime package/resource verification failed: $($_.Exception.Message). Review the diagnostics above. Open Sublime and let Package Control finish; on a new installation first use Tools > Install Package Control. Then run dot restore-apps -Only sublime -Check."
    }
}
}
if ($failures.Count) { throw "Windows app restore/check incomplete: $($failures -join '; ')" }
