@echo off
setlocal
set "DOT_PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
if defined ProgramW6432 set "DOT_PWSH=%ProgramW6432%\PowerShell\7\pwsh.exe"
if not exist "%DOT_PWSH%" goto bootstrap
"%DOT_PWSH%" -NoLogo -NoProfile -File "%~dp0dot.ps1" %*
exit /b %errorlevel%
:bootstrap
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0launch-dot.ps1" %*
exit /b %errorlevel%
