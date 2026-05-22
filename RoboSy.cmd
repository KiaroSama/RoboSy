@echo off
rem SPDX-License-Identifier: MIT
rem Copyright (c) 2026 Kiaro Sama
setlocal

set "ROBOSY_SCRIPT=%~dp0RoboSy.ps1"

if not exist "%ROBOSY_SCRIPT%" (
    echo RoboSy.ps1 was not found next to this command shim.
    pause
    exit /b 1
)

where pwsh.exe >nul 2>nul
if %errorlevel%==0 (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%ROBOSY_SCRIPT%" %*
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROBOSY_SCRIPT%" %*
)

exit /b %errorlevel%
