function Resolve-DotfilesTldrPython {
    $toolsRoot = & uv.exe tool dir
    if ($LASTEXITCODE -ne 0 -or -not $toolsRoot) { throw 'Cannot resolve uv tool directory.' }
    $python = Join-Path "$toolsRoot" 'tldr/Scripts/python.exe'
    if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
        throw 'Python TLDR is missing. Run dot packages -Apply -Only tldr.'
    }
    return $python
}

function Set-DotfilesTldrLauncher {
    param([string]$LocalBin = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.local/bin'))
    $python = Resolve-DotfilesTldrPython
    if (Test-Path -LiteralPath (Join-Path $localBin 'tldr.exe')) {
        throw 'A generated tldr.exe shadows the CMD launcher. Run dot packages -Apply -Only tldr to migrate it through uv.'
    }
    Write-DotfilesText (Join-Path $localBin 'tldr.cmd') ('@echo off' + "`r`n" + '"' + $python + '" -I -m tldr %*' + "`r`n")
}

function Install-DotfilesTldr {
    $toolsRoot = & uv.exe tool dir
    if ($LASTEXITCODE -ne 0 -or -not $toolsRoot) { throw 'Cannot resolve uv tool directory.' }
    $previousBin = $env:UV_TOOL_BIN_DIR
    try {
        # uv owns its generated executable, but it must not shadow tldr.cmd.
        # The receipt retains this destination across uv tool upgrades.
        $env:UV_TOOL_BIN_DIR = "$toolsRoot.tldr-bin"
        Invoke-DotfilesNative uv.exe @('tool','install','--force','tldr')
    } finally { $env:UV_TOOL_BIN_DIR = $previousBin }
    Set-DotfilesTldrLauncher
    Invoke-DotfilesNative (Resolve-DotfilesTldrPython) @('-I','-m','tldr','--version')
}

# Native process capture avoids PowerShell's shell-execution fallback, which can
# replace an application-control denial with a StandardOutputEncoding error.
function Invoke-DotfilesTldrProcess {
    param([string]$Argument, [string]$Executable, [string[]]$Prefix = @())
    if (-not $Executable) {
        $Executable = Resolve-DotfilesTldrPython
        $Prefix = @('-I','-m','tldr')
    }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = (Get-Command $Executable -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($item in @($Prefix) + @($Argument)) { $start.ArgumentList.Add($item) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        try { [void]$process.Start() }
        catch { throw "TLDR launch failed: $($_.Exception.GetBaseException().Message)" }
        # Read both pipes concurrently to avoid a full stderr pipe deadlocking stdout.
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $global:LASTEXITCODE = $process.ExitCode
        ($stdout.GetAwaiter().GetResult() + "`n" + $stderr.GetAwaiter().GetResult()) -split '\r?\n' |
            Where-Object { $_.Length -gt 0 }
    } finally { $process.Dispose() }
}

function Update-DotfilesTldr {
    param([switch]$DryRun)
    if ($DryRun) { Write-Output 'Preview: Python TLDR cache update (tldr --update)'; return }
    $version = Invoke-DotfilesTldrProcess --version
    if ($LASTEXITCODE -ne 0 -or "$version" -notmatch 'Client Specification') {
        throw 'Expected uv-managed Python TLDR. Repair it with dot packages -Apply -Only tldr.'
    }
    # Python TLDR 3.4.4 catches download errors and exits zero. Fail on any
    # reported error, including partial multilingual updates, or absent success.
    $output = @(Invoke-DotfilesTldrProcess --update)
    $code = $LASTEXITCODE
    $output | Write-Output
    if ($code -ne 0 -or @($output | Where-Object { "$_" -match '^Error:' }).Count -gt 0 -or
        @($output | Where-Object { "$_" -match '^Updated cache for language .+: [1-9][0-9]* entries$' }).Count -eq 0) {
        throw "TLDR cache update failed or returned no populated cache (exit $code)."
    }
    $global:LASTEXITCODE = 0
}
