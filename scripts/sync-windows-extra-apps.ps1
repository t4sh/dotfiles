#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Backup','Restore','Check')][string]$Mode='Check', [switch]$Apply,
    [string]$RoamingRoot=$env:APPDATA, [string]$LocalRoot=$env:LOCALAPPDATA,
    [string]$UserRoot=[Environment]::GetFolderPath('UserProfile'),
    [string]$RegistryRoot='HKCU:\Software',
    [string]$SnapshotRoot=(Join-Path (Split-Path $PSScriptRoot) 'apps/windows/extra'),
    [string]$BackupRoot=(Join-Path ([Environment]::GetFolderPath('UserProfile')) ('.dotfiles-backup/extra-apps-'+[guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'lib/windows-common.ps1')
. (Join-Path $PSScriptRoot 'lib/windows-extra-apps.ps1')
Assert-DotfilesWindows
# Public snapshots are curated; never replace them with this machine's settings.
if ($Mode -in @('Backup','Check')) { Write-Output "Public templates retained; live preference $Mode is intentionally skipped."; return }
$roots=@{Roaming=$RoamingRoot;Local=$LocalRoot;Registry=$RegistryRoot}

function Read-ExtraIni([string]$Path) {
    $data=[ordered]@{};$section=''
    foreach($line in [IO.File]::ReadAllLines($Path)){
        if($line -match '^\[([^\]]+)\](?:\s*[#;].*)?\s*$'){$section=$matches[1];if(-not $data.Contains($section)){$data[$section]=[ordered]@{}}}
        elseif($line -match '^([^#;\s][^=]*)=(.*)$'){
            $key=$matches[1].Trim();$value=$matches[2]
            if($section){$data[$section][$key]=$value}else{$data[$key]=$value}
        }
    }
    return $data
}
function Merge-ExtraIni([string]$Path,$Patch) {
    $remaining=[ordered]@{}
    foreach($key in $Patch.Keys){
        if($Patch[$key] -is [Collections.IDictionary]){foreach($child in $Patch[$key].Keys){$remaining["$key/$child"]=$Patch[$key][$child]}}
        else{$remaining[$key]=$Patch[$key]}
    }
    $lines=[Collections.Generic.List[string]]::new();$section=''
    # Append pending values before leaving each section; preserve unrelated text.
    function Flush-ExtraSection($Section) {
        foreach($key in @($remaining.Keys)){
            $parts=$key.Split('/',2);$owner=if($parts.Count -eq 2){$parts[0]}else{''}
            if($owner -eq $Section){$lines.Add("$($parts[-1])=$($remaining[$key])");$remaining.Remove($key)}
        }
    }
    if(Test-Path -LiteralPath $Path){
        foreach($line in [IO.File]::ReadAllLines($Path)){
            if($line -match '^\[([^\]]+)\](?:\s*[#;].*)?\s*$'){Flush-ExtraSection $section;$section=$matches[1]}
            if($line -match '^([^#;\s][^=]*)='){
                $key=if($section){"$section/$($matches[1].Trim())"}else{$matches[1].Trim()}
                if($remaining.Contains($key)){$lines.Add("$($key.Split('/')[-1])=$($remaining[$key])");$remaining.Remove($key);continue}
            }
            $lines.Add($line)
        }
    }
    Flush-ExtraSection $section
    foreach($key in @($remaining.Keys)){
        if(-not $remaining.Contains($key)){continue}
        $parts=$key.Split('/',2)
        if($parts.Count -eq 2){$lines.Add("[$($parts[0])]");Flush-ExtraSection $parts[0]}
        else{$lines.Insert(0,"$key=$($remaining[$key])");$remaining.Remove($key)}
    }
    return ($lines -join "`n")+"`n"
}
function Read-ExtraRegistry([string]$Path,[string[]]$Names) {
    $result=[ordered]@{}
    if(Test-Path -LiteralPath $Path){
        $key=Get-Item -LiteralPath $Path
        foreach($name in $Names){if($name -in $key.GetValueNames()){
            $kind=$key.GetValueKind($name).ToString()
            if($kind -notin @('String','ExpandString','DWord','QWord','MultiString')){throw 'Unsupported selected registry type.'}
            $result[$name]=[ordered]@{kind=$kind;value=$key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}
        }}
    }
    return $result
}
function Write-ExtraRegistry([string]$Path,$Patch) {
    # Registry New-Item -Force can replace an existing key and erase its values.
    if(-not (Test-Path -LiteralPath $Path)){$null=New-Item -Path $Path -Force}
    foreach($name in $Patch.Keys){
        $entry=$Patch[$name];$value=$entry.value
        switch($entry.kind){DWord {$value=[int]$value}; QWord {$value=[long]$value}; MultiString {$value=[string[]]$value}}
        $null=New-ItemProperty -LiteralPath $Path -Name $name -Value $value -PropertyType $entry.kind -Force
    }
}
function Read-ExtraLive($Spec,[string]$Path) {
    switch($Spec.Kind){
        registry {return Read-ExtraRegistry $Path $Spec.Paths}
        ini {return Read-ExtraIni $Path}
        snippet {return [IO.File]::ReadAllText($Path)}
        default {try{return ,(ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Path)) -AsHashtable -NoEnumerate)}catch{throw "Invalid JSON in $($Spec.App)/$($Spec.File); values not printed."}}
    }
}
$prepared=[Collections.Generic.List[hashtable]]::new();$failures=[Collections.Generic.List[string]]::new();$matched=0
foreach($spec in Get-DotfilesExtraAppSpecs){
    if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $SnapshotRoot $spec.App) $spec.File))) { continue }
    $live=Join-Path $roots[$spec.Root] $spec.Relative
    $snapshot=Join-Path (Join-Path $SnapshotRoot $spec.App) $spec.File
    $label="$($spec.App)/$($spec.File)"
    $source=if($Mode -eq 'Backup'){$live}else{$snapshot}
    if(-not (Test-Path -LiteralPath $source)){
        # Optional until first configured/captured. Never delete an earlier snapshot.
        if($Mode -eq 'Backup'){Write-Output "Not configured/preserved: $label"}
        elseif(Test-Path -LiteralPath $live){
            if($Mode -eq 'Check'){
                $uncaptured=Select-ExtraData (Read-ExtraLive $spec $live) $spec
                if($uncaptured.Count -gt 0 -or $spec.Kind -eq 'snippet'){$failures.Add("$label (not captured; run make backup)")}
            }else{Write-Warning "Not captured: $label"}
        }
        continue
    }
    if ($spec.Kind -ne 'registry' -and (Test-Path -LiteralPath $live -PathType Leaf)) { Assert-DotfilesPreferenceFile $live }
    $data=if($Mode -eq 'Backup'){Read-ExtraLive $spec $source}else{
        try{ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($source)) -AsHashtable -NoEnumerate}catch{throw "Invalid snapshot: $label"}
    }
    try{$patch=Select-ExtraData $data $spec}catch{throw "$label : $($_.Exception.Message)"}
    # Reject an edited snapshot that attempts to expand the reviewed allowlist.
    if($Mode -ne 'Backup' -and (Convert-ExtraJson $data) -cne (Convert-ExtraJson $patch)){throw "Snapshot includes unmanaged fields: $label"}
    if($spec.Kind -eq 'registry'){
        foreach($name in $patch.Keys){
            $entry=$patch[$name]
            if($entry -isnot [Collections.IDictionary] -or $entry.Count -ne 2 -or -not $entry.Contains('value') -or $entry.kind -notin @('String','ExpandString','DWord','QWord','MultiString')){throw "Invalid registry snapshot: $label"}
            switch($entry.kind){
                DWord {try{$null=[int]$entry.value}catch{throw "Invalid registry number: $label"}}
                QWord {try{$null=[long]$entry.value}catch{throw "Invalid registry number: $label"}}
                MultiString {if($entry.value -isnot [array] -or @($entry.value | Where-Object {$_ -isnot [string]}).Count){throw "Invalid registry string array: $label"}}
                default {if($entry.value -isnot [string]){throw "Invalid registry string: $label"}}
            }
        }
    }
    if($spec.Kind -eq 'ini'){
        foreach($value in $patch.Values){
            $leaves=if($value -is [Collections.IDictionary]){@($value.Values)}else{@($value)}
            foreach($leaf in $leaves){if($leaf -isnot [string] -or $leaf -match '[\r\n]'){throw "Invalid multiline/non-text INI preference: $label"}}
        }
    }
    $patch=Convert-ExtraPaths $patch $UserRoot -Restore:($Mode -ne 'Backup')
    Assert-ExtraSafe $patch
    if($Mode -eq 'Backup'){
        # An existing source reset to defaults supersedes an older snapshot.
        # Do not invent snapshots for never-configured optional surfaces.
        if($patch -is [Collections.IDictionary] -and $patch.Count -eq 0 -and -not (Test-Path -LiteralPath $snapshot)){Write-Output "No selected settings: $label";continue}
        $text=(ConvertTo-Json -InputObject $patch -Depth 80)+"`n"
        $text=$text.Replace("`r`n","`n")
        if((Test-Path -LiteralPath $snapshot) -and [IO.File]::ReadAllText($snapshot) -ceq $text){$matched++;continue}
        $prepared.Add(@{Target=$snapshot;Text=$text;Registry=$false;Label=$label});continue
    }
    $exists=Test-Path -LiteralPath $live
    $current=if($exists){Read-ExtraLive $spec $live}else{[ordered]@{}}
    if($exists){Assert-ExtraRoot $current $spec}
    # Empty object captures own no settings and need no file/key on a fresh PC.
    if($patch -is [Collections.IDictionary] -and $patch.Count -eq 0){$matched++;continue}
    # Compare only snapshot-owned leaves; arrays are a managed unit.
    $merged=Merge-ExtraPreferences (ConvertFrom-Json -InputObject (Convert-ExtraJson $current) -AsHashtable -NoEnumerate) $patch
    if($exists -and (Convert-ExtraJson $current) -ceq (Convert-ExtraJson $merged)){$matched++;continue}
    if($Mode -eq 'Check'){$failures.Add($label);continue}
    if($Apply -and @(Get-Process -Name $spec.Process -ErrorAction SilentlyContinue).Count){$failures.Add("$label (close the app and retry)");continue}
    if($spec.Kind -eq 'registry'){$prepared.Add(@{Target=$live;Patch=$patch;Previous=$current;Registry=$true;Label=$label});continue}
    $text=switch($spec.Kind){
        snippet { $patch }
        ini { Merge-ExtraIni $live $patch }
        default { (ConvertTo-Json -InputObject $merged -Depth 80)+"`n" }
    }
    $prepared.Add(@{Target=$live;Text=$text.Replace("`r`n","`n");Registry=$false;Label=$label})
}
if($failures.Count){$failures | ForEach-Object {Write-Warning "Preference drift/deferred: $_"};throw 'Extended Windows preferences incomplete; no changes published.'}
if($Mode -eq 'Check'){Write-Output "Extended Windows preferences match: $matched surfaces.";return}
if($Mode -eq 'Backup' -and $prepared.Count){
    # Scan only the projected payload over stdin: no raw profile or temporary
    # secret-bearing file is written to the repository, even on scan failure.
    $scanner=(Get-Command gitleaks.exe -ErrorAction Stop).Source
    ($prepared | ForEach-Object {$_.Text}) -join "`n" | & $scanner stdin --redact --no-banner
    if($LASTEXITCODE -ne 0){throw 'Selected app backup failed the secret scan; nothing published.'}
}
if(-not $Apply){$prepared | ForEach-Object {Write-Output "Preview $Mode : $($_.Label)"};Write-Output "Unchanged: $matched surfaces.";return}
# All selected inputs were validated before publication. Keep recovery copies
# outside Git and roll back already-published surfaces if a later write fails.
$published=[Collections.Generic.List[hashtable]]::new()
try{
    foreach($item in $prepared){
        $hadTarget=Test-Path -LiteralPath $item.Target
        $backup=Join-Path $BackupRoot ([guid]::NewGuid().ToString('N'))
        if($item.Registry){
            Write-DotfilesText $backup (Convert-ExtraJson $item.Previous)
            # Include the current item so partial value writes are also rolled back.
            $published.Add(@{Item=$item;Backup=$backup;Existed=$hadTarget})
            Write-ExtraRegistry $item.Target $item.Patch
        }else{
            if($hadTarget){[IO.Directory]::CreateDirectory($BackupRoot)|Out-Null;Copy-Item -LiteralPath $item.Target -Destination $backup}
            $stage=$item.Target+'.stage-'+[guid]::NewGuid().ToString('N')
            try{Write-DotfilesText $stage $item.Text;Move-Item -LiteralPath $stage -Destination $item.Target -Force}
            finally{if(Test-Path -LiteralPath $stage){Remove-Item -LiteralPath $stage}}
            $published.Add(@{Item=$item;Backup=$backup;Existed=$hadTarget})
        }
        Write-Output "$Mode : $($item.Label)"
    }
}catch{
    $originalError=$_
    $rollbackFailures=[Collections.Generic.List[string]]::new()
    for($i=$published.Count-1;$i -ge 0;$i--){
        $record=$published[$i];$item=$record.Item
        try{
            if($item.Registry){
                Write-ExtraRegistry $item.Target $item.Previous
                foreach($name in $item.Patch.Keys){
                    if(-not $item.Previous.Contains($name) -and (Get-Item -LiteralPath $item.Target).GetValueNames() -contains $name){
                        Remove-ItemProperty -LiteralPath $item.Target -Name $name -ErrorAction Stop
                    }
                }
            }elseif($record.Existed){Copy-Item -LiteralPath $record.Backup -Destination $item.Target -Force}
            elseif(Test-Path -LiteralPath $item.Target){Remove-Item -LiteralPath $item.Target}
        }catch{
            $rollbackFailures.Add("$($item.Label) (target: $($item.Target); recovery: $($record.Backup))")
        }
    }
    if($rollbackFailures.Count){throw [InvalidOperationException]::new("Publication failed; rollback incomplete for: $($rollbackFailures -join '; '). Original error: $($originalError.Exception.Message)",$originalError.Exception)}
    throw $originalError
}
Write-Output "$Mode complete: $($prepared.Count) extended Windows surfaces; $matched unchanged. Recovery copies: $BackupRoot"
