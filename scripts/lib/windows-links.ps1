# Equal bytes do not prove that two paths are a hardlink to the same file.
function Test-DotfilesSameFile([string]$Left, [string]$Right) {
    if (-not ('DotfilesFileIdentity' -as [type])) {
        Add-Type @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class DotfilesFileIdentity {
  [StructLayout(LayoutKind.Sequential)] struct Info {
    public uint Attributes; public System.Runtime.InteropServices.ComTypes.FILETIME Creation, Access, Write;
    public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
  }
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle h, out Info i);
  public static bool Same(string a, string b) {
    using(var x = File.Open(a, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
    using(var y = File.Open(b, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) {
      Info i,j;
      if(!GetFileInformationByHandle(x.SafeFileHandle,out i) || !GetFileInformationByHandle(y.SafeFileHandle,out j)) throw new IOException("Cannot determine file identity");
      return i.Volume==j.Volume && i.IndexHigh==j.IndexHigh && i.IndexLow==j.IndexLow;
    }
  }
}
'@
    }
    return [DotfilesFileIdentity]::Same($Left,$Right)
}
function Get-DotfilesLinkMode([string]$Source,[string]$Target) {
    if (-not (Test-Path -LiteralPath $Source)) { throw "Missing source: $Source" }
    # Check physical files before identity checks or repair can accept an MSIX
    # overlay as an ordinary consumer. Set-DotfilesLink shares this guard.
    if (Test-Path -LiteralPath $Source -PathType Leaf) { Assert-DotfilesPreferenceFile $Source }
    if (Test-Path -LiteralPath $Target -PathType Leaf) { Assert-DotfilesPreferenceFile $Target }
    $item = Get-Item -LiteralPath $Target -Force -ErrorAction SilentlyContinue
    if (-not $item) { return 'Missing' }
    if ($item.LinkType -in @('SymbolicLink','Junction')) {
        $resolved = $item.ResolveLinkTarget($true)
        if ($resolved -and [IO.Path]::GetFullPath($resolved.FullName) -ieq [IO.Path]::GetFullPath($Source)) { return $item.LinkType }
        return 'WrongLink'
    }
    if ($item.PSIsContainer) { return 'DirectoryConflict' }
    if (Test-Path -LiteralPath $Source -PathType Container) { return 'FileConflict' }
    if (Test-DotfilesSameFile $Source $Target) { return 'HardLink' }
    return 'PlainFile'
}
function Set-DotfilesLink([string]$Source,[string]$Target) {
    $mode = Get-DotfilesLinkMode $Source $Target
    if ($mode -in @('SymbolicLink','HardLink','Junction')) { return }
    if ($mode -eq 'DirectoryConflict') { throw "Preserved existing directory: $Target. Reconcile it before linking." }
    $parent = Split-Path $Target -Parent
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $candidate = Join-Path $parent ('.dotfiles-link-'+[guid]::NewGuid().ToString('N'))
    $backup = $Target + '.backup-' + [guid]::NewGuid().ToString('N')
    $hadTarget = [bool](Get-Item -LiteralPath $Target -Force -ErrorAction SilentlyContinue)
    try {
        if (Test-Path -LiteralPath $Source -PathType Container) {
            New-Item -ItemType Junction -Path $candidate -Target $Source | Out-Null
        } else {
            try { New-Item -ItemType SymbolicLink -Path $candidate -Target $Source -ErrorAction Stop | Out-Null }
            catch { New-Item -ItemType HardLink -Path $candidate -Target $Source -ErrorAction Stop | Out-Null }
        }
        if ($hadTarget) { Move-Item -LiteralPath $Target -Destination $backup }
        try { Move-Item -LiteralPath $candidate -Destination $Target }
        catch { if ($hadTarget) { Move-Item -LiteralPath $backup -Destination $Target }; throw }
        Write-Output "$(Get-DotfilesLinkMode $Source $Target) : $Target"
    } finally {
        $leftover = Get-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
        if ($leftover) { if ($leftover.PSIsContainer) { [IO.Directory]::Delete($candidate) } else { [IO.File]::Delete($candidate) } }
    }
}
