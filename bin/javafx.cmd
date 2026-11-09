@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0javafx-impl.ps1" %*
exit /b %ERRORLEVEL%
