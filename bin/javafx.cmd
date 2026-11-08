@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0javafx.ps1" %*
exit /b %ERRORLEVEL%
