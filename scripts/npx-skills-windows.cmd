@echo off
setlocal
if not defined NPX_REAL (
  echo NPX_REAL is not set. This wrapper is managed by update-windows.ps1. 1>&2
  exit /b 1
)
if not defined DOTFILES_SKILLS_AGENT set "DOTFILES_SKILLS_AGENT=codex"
if /I not "%DOTFILES_SKILLS_AGENT%"=="codex" (
  echo Unsupported global skill target. Canonical skills use codex with client junctions. 1>&2
  exit /b 1
)
call "%NPX_REAL%" %* --agent codex
exit /b %errorlevel%
