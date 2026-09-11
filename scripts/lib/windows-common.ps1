# Shared native Windows discovery. Dot-sourcing this file does not mutate state.
function Assert-DotfilesWindows {
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'This entry point requires Windows.' }
    if ($PSHOME -match '[\\/]WindowsApps[\\/]') { throw 'Run this workflow in standard MSI PowerShell, not Store PowerShell: packaged AppData redirection can target different user files.' }
}
function Resolve-DotfilesPwsh {
    # 32-bit Make/Windows PowerShell sees ProgramFiles as Program Files (x86).
    $candidates = @()
    if ($env:ProgramW6432) { $candidates += Join-Path $env:ProgramW6432 'PowerShell\7\pwsh.exe' }
    $candidates += Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    $candidates += @(Get-Command pwsh.exe -All -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
    foreach ($candidate in $candidates) {
        if ($candidate -notmatch '[\\/](\.cache|\.codex|WindowsApps)[\\/]|codex.*runtime' -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            $versionText = (Get-Item -LiteralPath $candidate).VersionInfo.ProductVersion
            if ($versionText -match '^(\d+\.\d+\.\d+)(?:\s|\+|$)' -and [version]$Matches[1] -ge [version]'7.4.0') { return $candidate }
        }
    }
    throw 'Standard PowerShell 7.4 or newer is required. Run install.ps1 -Apply from Windows PowerShell to install or upgrade it. Store PowerShell is excluded because packaged AppData redirection can read or write the wrong preferences.'
}
function Assert-DotfilesPersistentScriptPolicy {
    # Ignore bootstrap's temporary Process Bypass: new shells must work too.
    foreach ($scope in @('MachinePolicy','UserPolicy','CurrentUser','LocalMachine')) {
        $policy = [string](Get-ExecutionPolicy -Scope $scope)
        if ($policy -eq 'Undefined') { continue }
        if ($policy -in @('RemoteSigned','Unrestricted','Bypass')) { return }
        throw "Persistent execution policy is $policy at $scope. Dotfiles requires RemoteSigned or an existing less restrictive policy. See WINDOWS.md; Group Policy must be resolved by your administrator. No setup started."
    }
    throw 'No persistent script policy is configured (Windows defaults to Restricted). Run Set-ExecutionPolicy -Scope CurrentUser RemoteSigned, then open a new shell before setup. No setup started.'
}
function Assert-DotfilesPreferenceFile([string]$Path) {
    # Inspect the opened file, not process ancestry: MSIX overlays can serve a
    # different file even when PSHOME and APPDATA both report ordinary paths.
    if (-not ('Dotfiles.FilePath' -as [type])) {
        Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;
namespace Dotfiles {
    public static class FilePath {
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        public static extern uint GetFinalPathNameByHandle(SafeFileHandle file, StringBuilder path, uint size, uint flags);
    }
}
'@
    }
    $file = [IO.File]::Open($Path,'Open','Read','ReadWrite,Delete')
    try {
        $buffer = [Text.StringBuilder]::new(32768)
        $length = [Dotfiles.FilePath]::GetFinalPathNameByHandle($file.SafeFileHandle,$buffer,$buffer.Capacity,0)
        if (-not $length -or $length -ge $buffer.Capacity) { throw 'Cannot verify preference file location; file preserved.' }
        if ($buffer.ToString() -match '[\\/]Packages[\\/][^\\/]+[\\/]LocalCache[\\/]' -and $Path -notmatch '[\\/]Packages[\\/][^\\/]+[\\/]LocalCache[\\/]') {
            throw 'Preference file is redirected into an MSIX LocalCache. Open standard PowerShell directly from Windows Run or Explorer and retry; no preference files published by this stage.'
        }
    } finally { $file.Dispose() }
}
function Resolve-DotfilesBash {
    param([string]$GitPath = (Get-Command git.exe -ErrorAction Stop).Source)
    $root = Split-Path (Split-Path $GitPath -Parent) -Parent
    foreach ($candidate in @((Join-Path $root 'bin\bash.exe'), (Join-Path $root 'usr\bin\bash.exe'))) {
        if ((Test-Path -LiteralPath $candidate) -and (Test-Path -LiteralPath (Join-Path $root 'cmd\git.exe'))) { return $candidate }
    }
    throw 'Cannot locate Git for Windows Bash beside git.exe. Install Git for Windows and repair PATH; WSL bash is not supported.'
}
function Resolve-DotfilesPython {
    $uv = (Get-Command uv.exe -ErrorAction Stop).Source
    $candidate = @(& $uv python find --managed-python 2>$null)
    if ($LASTEXITCODE -ne 0 -or $candidate.Count -ne 1 -or -not (Test-Path -LiteralPath $candidate[0] -PathType Leaf)) { throw 'Managed Python is missing. Run: uv python install' }
    return $candidate[0]
}
function Resolve-DotfilesVoltaRuntime {
    param([ValidateSet('node','npx')][string]$Name)
    $volta = Get-Command volta.exe -ErrorAction Stop
    $runtime = Join-Path (Split-Path $volta.Source -Parent) ($Name+'.exe')
    if (-not (Test-Path -LiteralPath $runtime -PathType Leaf)) { throw "Volta runtime shim missing: $Name. Repair the Volta installation." }
    return $runtime
}
function Invoke-DotfilesNative {
    param([Parameter(Mandatory)][string]$File, [string[]]$Arguments = @(), [int[]]$SuccessCodes = @(0))
    & $File @Arguments
    if ($LASTEXITCODE -notin $SuccessCodes) { throw "$([IO.Path]::GetFileName($File)) failed (exit $LASTEXITCODE)" }
    $global:LASTEXITCODE = 0 # Only after an explicitly accepted result.
}
function Invoke-DotfilesNativeUtf8 {
    param([Parameter(Mandatory)][string]$File, [string[]]$Arguments = @())
    # Git Bash and Python emit UTF-8 into pipes; the inherited OEM code page
    # otherwise turns arrows/checkmarks into mojibake before filters see them.
    $previousEncoding = [Console]::OutputEncoding
    $previousPythonEncoding = $env:PYTHONIOENCODING
    try {
        [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
        $env:PYTHONIOENCODING = 'utf-8'
        Invoke-DotfilesNative $File $Arguments
    } finally {
        [Console]::OutputEncoding = $previousEncoding
        $env:PYTHONIOENCODING = $previousPythonEncoding
    }
}
function Merge-DotfilesPath {
    param([string[]]$Segments)
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $result = foreach ($segment in $Segments) {
        foreach ($entry in ($segment -split ';')) {
            $entry = $entry.Trim()
            if ($entry -and $seen.Add($entry.TrimEnd('\','/'))) { $entry }
        }
    }
    return ($result -join ';')
}
function Write-DotfilesText {
    param([string]$Path, [string]$Text)
    if ((Test-Path -LiteralPath $Path -PathType Leaf) -and [IO.File]::ReadAllText($Path) -ceq $Text) { return }
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
function Resolve-DotfilesPrivateSource([string]$ProfileRoot, [string]$Source) {
    if ($Source -match '(^[/\\]|:|(^|[/\\])\.\.([/\\]|$))') { throw 'Invalid private backup source path.' }
    # A substituted profile isolates ALL roots for disposable recovery tests.
    $live = [IO.Path]::GetFullPath($ProfileRoot).TrimEnd('\') -ieq [Environment]::GetFolderPath('UserProfile').TrimEnd('\')
    if ($Source.StartsWith('@ProgramData/')) {
        $base = if ($live) { [Environment]::GetFolderPath('CommonApplicationData') } else { Join-Path $ProfileRoot 'ProgramData' }
        return Join-Path $base $Source.Substring(13)
    }
    if ($Source.StartsWith('@Roaming/')) {
        $base = if ($live) { [Environment]::GetFolderPath('ApplicationData') } else { Join-Path $ProfileRoot 'AppData/Roaming' }
        return Join-Path $base $Source.Substring(9)
    }
    if ($Source.StartsWith('@')) { throw 'Unknown private backup source root.' }
    return Join-Path $ProfileRoot $Source
}
