@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0javafxc-impl.ps1" %*
exit /b %ERRORLEVEL%
