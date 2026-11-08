@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0javafxc.ps1" %*
exit /b %ERRORLEVEL%
