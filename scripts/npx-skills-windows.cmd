@echo off
setlocal
if not defined NPX_REAL (
  echo NPX_REAL is not set. This wrapper is managed by update-windows.ps1. 1>&2
  exit /b 1
)
echo Checking skills from source: %~3
if not defined PYTHON_BIN (
  echo PYTHON_BIN is not set. Run skills through update-windows.ps1. 1>&2
  exit /b 1
)
set "SKILL_LOG=%TEMP%\dotfiles-skills-%RANDOM%-%RANDOM%.log"
rem npm options must precede the positional command; the trailing -y is for skills.
rem Never wait on a hidden prompt in this unattended maintenance wrapper.
rem Skillsfile owns the explicit --agent codex selector; do not append it twice.
call "%NPX_REAL%" --yes %* <nul >"%SKILL_LOG%" 2>&1
set "SKILL_EXIT=%errorlevel%"
"%PYTHON_BIN%" "%~dp0summarize-skills-update.py" "%SKILL_EXIT%" "%SKILL_LOG%" %*
exit /b %SKILL_EXIT%
