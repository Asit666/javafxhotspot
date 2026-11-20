@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0javafxupdate-impl.ps1" %*
exit /b %ERRORLEVEL%
