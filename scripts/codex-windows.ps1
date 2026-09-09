$ErrorActionPreference = 'Stop'
$candidates = @(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin') -Filter codex.exe -File -Recurse |
    Sort-Object LastWriteTimeUtc -Descending)
if ($candidates.Count -eq 0) { throw 'Codex desktop CLI was not found. Install or repair the Codex desktop app.' }
& $candidates[0].FullName @args
exit $LASTEXITCODE
